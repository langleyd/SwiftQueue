// The MIT License (MIT)
//
// Copyright (c) 2017 Lucas Nelaupe
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation

internal final class SqOperationQueue: OperationQueue {

    private let params: SqManagerParams

    private let creator: JobCreator
    private let queue: Queue

    private let persister: JobPersister
    private let serializer: JobInfoSerializer
    private let logger: SwiftQueueLogger
    private let listener: JobListener?

    private let trigger: Operation = TriggerOperation()

    init(_ params: SqManagerParams, _ queue: Queue, _ isSuspended: Bool) {
        self.params = params
        self.queue = queue
        self.creator = params.jobCreator

        self.persister = params.persister
        self.serializer = params.serializer
        self.logger = params.logger
        self.listener = params.listener

        super.init()

        self.isSuspended = isSuspended

        self.name = queue.name
        self.maxConcurrentOperationCount = queue.maxConcurrent

        if params.initInBackground {
            params.dispatchQueue.async { [weak self] in
                self?.loadSerializedTasks(name: queue.name)
            }
        } else {
            self.loadSerializedTasks(name: queue.name)
        }
    }

    private func loadSerializedTasks(name: String) {
        persister.restore(queueName: name).compactMap { string -> SqOperation? in
            do {
                let info = try serializer.deserialize(json: string)
                let job = creator.create(type: info.type, params: info.params)

                return SqOperation(job: job, info: info, logger: logger, listener: listener, dispatchQueue: params.dispatchQueue)
            } catch let error {
                logger.log(.error, jobId: "UNKNOWN", message: "Unable to deserialize job error=\(error.localizedDescription)")
                return nil
            }
        }.sorted { operation, operation2 in
            operation.info.createTime < operation2.info.createTime
        }.forEach { operation in
            self.addOperationInternal(operation, wait: false)
        }
        super.addOperation(trigger)
    }

    override func addOperation(_ ope: Operation) {
        self.addOperationInternal(ope, wait: true)
    }

    private func addOperationInternal(_ ope: Operation, wait: Bool) {
        guard !ope.isFinished else { return }

        if wait {
            ope.addDependency(trigger)
        }

        guard let job = ope as? SqOperation else {
            // Not a job Task I don't care
            super.addOperation(ope)
            return
        }

        do {
            try job.willScheduleJob(queue: self)
        } catch let error {
            job.abort(error: error)
            return
        }

        // Serialize this operation
        if job.info.isPersisted {
            persistJob(job: job)
        }
        job.completionBlock = { [weak self] in
            self?.completed(job)
        }
        super.addOperation(job)
    }

    func persistJob(job: SqOperation) {
        do {
            let data = try serializer.serialize(info: job.info)
            persister.put(queueName: queue.name, taskId: job.info.uuid, data: data)
        } catch let error {
            // In this case we still try to run the job
            logger.log(.error, jobId: job.info.uuid, message: "Unable to serialize job error=\(error.localizedDescription)")
        }
    }

    func cancelOperations(tag: String) {
        for case let operation as SqOperation in operations where operation.info.tags.contains(tag) {
            operation.cancel()
        }
    }

    func cancelOperations(uuid: String) {
        for case let operation as SqOperation in operations where operation.info.uuid == uuid {
            operation.cancel()
        }
    }

    private func completed(_ job: SqOperation) {
        // Remove this operation from serialization
        if job.info.isPersisted {
            persister.remove(queueName: queue.name, taskId: job.info.uuid)
        }

        job.remove()
    }

    func createHandler(type: String, params: [String: Any]?) -> Job {
        return creator.create(type: type, params: params)
    }

}

internal class TriggerOperation: Operation {}
