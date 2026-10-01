import AuthenticationServices
#if canImport(UIKit)
import UIKit
#endif

/// Drives `ASAuthorizationController` directly rather than using the pre-styled
/// `SignInWithAppleButton` widget, so the trigger can be a plain button inside a native
/// SwiftUI `.alert()` instead of Apple's branded button — the alert can only host plain
/// `Button`s, not arbitrary custom views, so this coordinator performs the same
/// system-level Sign in with Apple flow programmatically.
@MainActor
final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    var onCompletion: ((Result<ASAuthorization, Error>) -> Void)?

    func signIn(nonce: String) {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        // Deliberately not requesting .email: Vestigo never uses it, and Apple only ever
        // sends it on the very first authorization anyway. .fullName IS requested as a
        // one-time convenience to prefill `settings.name` when it's still empty — but since
        // Apple only ever provides it on that first authorization (never on later sign-ins,
        // reinstalls, or token refreshes), this can't be relied on as a sync mechanism; the
        // display name shown to friends is still sourced from `settings.name` itself.
        request.requestedScopes = [.fullName]
        request.nonce = SupabaseAuthClient.sha256Hex(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let keyWindow = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) {
            return keyWindow
        }
        // This delegate method is only ever invoked while presenting UI, so a connected
        // window scene is always expected to exist at this point.
        return UIWindow(windowScene: scenes.first!)
        #else
        return ASPresentationAnchor()
        #endif
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        onCompletion?(.success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        onCompletion?(.failure(error))
    }
}
