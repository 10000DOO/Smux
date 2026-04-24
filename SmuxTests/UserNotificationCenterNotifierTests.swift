import UserNotifications
import XCTest
@testable import Smux

final class UserNotificationCenterNotifierTests: XCTestCase {
    @MainActor
    func testNotifierPreparesAuthorizationAndSchedulesDomainDelivery() async {
        let center = RecordingUserNotificationCenter()
        let notifier = UserNotificationCenterNotifier(center: center)
        let delivery = SystemNotificationDelivery(
            identifier: "notification-id",
            title: "Smux task completed",
            body: "Done",
            interruption: .passive,
            userInfo: [
                "workspaceNotificationID": "notification-id",
                "workspaceID": "workspace-id"
            ]
        )
        let prepareExpectation = expectation(description: "prepare completion")
        var prepareResult: Result<Bool, any Error>?

        notifier.prepare { result in
            prepareResult = result
            prepareExpectation.fulfill()
        }
        notifier.deliver(delivery) { _ in }

        await fulfillment(of: [prepareExpectation], timeout: 1)
        XCTAssertEqual(try prepareResult?.get(), true)
        XCTAssertEqual(center.authorizationOptions, [.alert, .sound])
        XCTAssertEqual(center.requests.map(\.identifier), ["notification-id"])
        XCTAssertEqual(center.requests.first?.content.title, "Smux task completed")
        XCTAssertEqual(center.requests.first?.content.body, "Done")
        XCTAssertEqual(
            center.requests.first?.content.userInfo["workspaceNotificationID"] as? String,
            "notification-id"
        )
        XCTAssertEqual(center.requests.first?.content.interruptionLevel, .passive)
    }

    @MainActor
    func testNotifierAssignsItselfAsNotificationCenterDelegate() {
        let center = RecordingUserNotificationCenter()
        let notifier = UserNotificationCenterNotifier(center: center)

        XCTAssertTrue(center.delegate === notifier)
    }

    @MainActor
    func testNotifierUsesBannerAndSoundForForegroundPresentation() {
        let center = RecordingUserNotificationCenter()
        let notifier = UserNotificationCenterNotifier(center: center)

        XCTAssertEqual(notifier.foregroundPresentationOptions, [.banner, .sound])
    }

    @MainActor
    func testNotifierPreservesDeliveryCompletionHandler() {
        let center = RecordingUserNotificationCenter()
        let notifier = UserNotificationCenterNotifier(center: center)
        let delivery = SystemNotificationDelivery(
            identifier: "notification-id",
            title: "Smux task completed",
            body: "Done",
            interruption: .passive,
            userInfo: [:]
        )

        notifier.deliver(delivery) { _ in }

        XCTAssertTrue(center.didReceiveAddCompletionHandler)
    }

    @MainActor
    func testNotifierPropagatesPrepareAuthorizationResult() async {
        let center = RecordingUserNotificationCenter()
        center.authorizationResult = (false, nil)
        let notifier = UserNotificationCenterNotifier(center: center)
        let prepareExpectation = expectation(description: "prepare completion")
        var authorizationResult: Result<Bool, any Error>?

        notifier.prepare { result in
            authorizationResult = result
            prepareExpectation.fulfill()
        }

        await fulfillment(of: [prepareExpectation], timeout: 1)
        XCTAssertEqual(try authorizationResult?.get(), false)
    }

    @MainActor
    func testNotifierPropagatesPrepareError() async {
        let center = RecordingUserNotificationCenter()
        center.authorizationResult = (false, RecordingUserNotificationCenter.TestError.authorizationFailed)
        let notifier = UserNotificationCenterNotifier(center: center)
        let prepareExpectation = expectation(description: "prepare completion")
        var receivedError: Error?

        notifier.prepare { result in
            if case let .failure(error) = result {
                receivedError = error
            }
            prepareExpectation.fulfill()
        }

        await fulfillment(of: [prepareExpectation], timeout: 1)
        XCTAssertTrue(receivedError is RecordingUserNotificationCenter.TestError)
    }

    @MainActor
    func testNotifierPropagatesDeliveryResult() async {
        let center = RecordingUserNotificationCenter()
        let notifier = UserNotificationCenterNotifier(center: center)
        let delivery = SystemNotificationDelivery(
            identifier: "notification-id",
            title: "Smux task completed",
            body: "Done",
            interruption: .passive,
            userInfo: [:]
        )
        let deliveryExpectation = expectation(description: "delivery completion")
        var deliveryResult: Result<Void, any Error>?

        notifier.deliver(delivery) { result in
            deliveryResult = result
            deliveryExpectation.fulfill()
        }

        await fulfillment(of: [deliveryExpectation], timeout: 1)
        XCTAssertNoThrow(try deliveryResult?.get())
    }

    @MainActor
    func testNotifierPropagatesDeliveryError() async {
        let center = RecordingUserNotificationCenter()
        center.addError = RecordingUserNotificationCenter.TestError.deliveryFailed
        let notifier = UserNotificationCenterNotifier(center: center)
        let delivery = SystemNotificationDelivery(
            identifier: "notification-id",
            title: "Smux task completed",
            body: "Done",
            interruption: .passive,
            userInfo: [:]
        )
        let deliveryExpectation = expectation(description: "delivery completion")
        var receivedError: Error?

        notifier.deliver(delivery) { result in
            if case let .failure(error) = result {
                receivedError = error
            }
            deliveryExpectation.fulfill()
        }

        await fulfillment(of: [deliveryExpectation], timeout: 1)
        XCTAssertTrue(receivedError is RecordingUserNotificationCenter.TestError)
    }
}

private final class RecordingUserNotificationCenter: UserNotificationScheduling {
    enum TestError: Error {
        case authorizationFailed
        case deliveryFailed
    }

    weak var delegate: (any UNUserNotificationCenterDelegate)?
    private(set) var authorizationOptions: UNAuthorizationOptions?
    private(set) var requests: [UNNotificationRequest] = []
    private(set) var didReceiveAddCompletionHandler = false
    var authorizationResult: (Bool, Error?) = (true, nil)
    var addError: Error?

    @MainActor
    init() {}

    func requestAuthorization(
        options: UNAuthorizationOptions,
        completionHandler: @escaping @Sendable (Bool, Error?) -> Void
    ) {
        authorizationOptions = options
        completionHandler(authorizationResult.0, authorizationResult.1)
    }

    func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?
    ) {
        requests.append(request)
        didReceiveAddCompletionHandler = completionHandler != nil
        completionHandler?(addError)
    }
}
