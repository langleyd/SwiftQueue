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

import XCTest
@testable import SwiftQueue

class StartStopTests: XCTestCase {

    func testScheduleWhenQueueStop() {
        let (type, job) = (UUID().uuidString, TestJob())

        let creator = TestCreator([type: job])

        let manager = SwiftQueueManagerBuilder(creator: creator)
                .set(persister: NoSerializer.shared)
                .set(isSuspended: true)
                .build()

        JobBuilder(type: type).schedule(manager: manager)

        // No run
        job.assertNoRun()

        manager.isSuspended = false

        job.awaitForRemoval()
        job.assertSingleCompletion()
    }

    func testSchedulePeriodicJobThenStart() {
        let (type, job) = (UUID().uuidString, TestJob())

        let creator = TestCreator([type: job])

        let manager = SwiftQueueManagerBuilder(creator: creator).set(persister: NoSerializer.shared).build()

        manager.isSuspended = true

        JobBuilder(type: type).periodic(limit: .limited(4), interval: 0).schedule(manager: manager)

        // No run
        job.assertNoRun()

        manager.isSuspended = false
        manager.isSuspended = false
        manager.isSuspended = false
        manager.isSuspended = false
        manager.isSuspended = false
        manager.isSuspended = false
        manager.isSuspended = false

        job.awaitForRemoval()

        job.assertRunCount(expected: 4)
        job.assertCompletedCount(expected: 1)
        job.assertRetriedCount(expected: 0)
        job.assertCanceledCount(expected: 0)
        job.assertNoError()
    }

}
