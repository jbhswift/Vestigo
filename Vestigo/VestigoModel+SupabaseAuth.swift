import Foundation
import AuthenticationServices

extension VestigoModel {

    /// Called on every entry to the Friends tab, not just the first — deliberately
    /// re-validates rather than trusting a cached "already signed in" flag, so that if
    /// Apple ID access was revoked or the refresh token became invalid since last time,
    /// the prompt reappears instead of silently leaving the user in a half-signed-in state.
    /// Remembers which tab the user came from so cancelling can return them there.
    func ensureSupabaseSession(previousTab: AppTab) {
        Task {
            let token = await supabaseAuth.currentAccessToken()
            isSupabaseSignedIn = (token != nil)
            if token == nil {
                tabBeforeSignInPrompt = previousTab
                returnToPreviousTabOnSignInCancel = true
                showSignInWithApple = true
            }
        }
    }

    /// Called from the inline "sign in to share or receive" notice shown when the user is
    /// already sitting on the Friends tab without a session. Cancelling this one should
    /// just dismiss the alert and leave them on Friends, not navigate away.
    func presentSignInWithApple() {
        returnToPreviousTabOnSignInCancel = false
        showSignInWithApple = true
    }

    /// Called by the alert's "Sign In" button. Starts the real system Sign in with Apple
    /// flow via `AppleSignInCoordinator` rather than the pre-styled button widget, since
    /// a native `.alert()` can only host plain buttons.
    func beginAppleSignIn() {
        let rawNonce = SupabaseAuthClient.makeRawNonce()
        pendingSignInNonce = rawNonce
        appleSignInCoordinator.onCompletion = { [weak self] result in
            self?.handleAppleAuthorizationResult(result)
        }
        appleSignInCoordinator.signIn(nonce: rawNonce)
    }

    /// Called from the alert's "Cancel" button. Only navigates away if this particular
    /// prompt was the tab-entry kind (see `ensureSupabaseSession`); the inline-notice kind
    /// leaves the user right where they were.
    func handleSignInWithAppleDismissed() {
        showSignInWithApple = false
        Task {
            let token = await supabaseAuth.currentAccessToken()
            isSupabaseSignedIn = (token != nil)
            if token == nil && returnToPreviousTabOnSignInCancel {
                selectTab(tabBeforeSignInPrompt)
            }
        }
    }

    private func handleAppleAuthorizationResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            signInErrorMessage = error.localizedDescription
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = pendingSignInNonce else {
                signInErrorMessage = "Apple didn't return a usable credential."
                return
            }
            // One-time convenience: Apple only includes fullName on the very first
            // authorization ever, so this only ever fires once — never overwrites a name
            // the user already set, and remains fully editable afterward either way.
            if settings.name.isEmpty, let fullName = credential.fullName {
                let formatted = PersonNameComponentsFormatter.localizedString(from: fullName, style: .default)
                if !formatted.isEmpty {
                    settings.name = formatted
                    saveSettings()
                }
            }
            Task {
                do {
                    try await completeSupabaseSignIn(idToken: idToken, rawNonce: nonce)
                } catch {
                    signInErrorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Completes the Supabase side of sign-in once Apple has returned a credential.
    private func completeSupabaseSignIn(idToken: String, rawNonce: String) async throws {
        _ = try await supabaseAuth.signInWithApple(idToken: idToken, rawNonce: rawNonce)
        isSupabaseSignedIn = true
        showSignInWithApple = false
        await supabaseAuth.updateDisplayName(settings.name)
    }

    /// "Delete my Vestigo account" — distinct from "Clear all data": this removes the
    /// Friends identity (profile, friendships, invites, shared library snapshots) via
    /// cascade on the server; it never touches the personal movie library on this device.
    func deleteSupabaseAccount() async {
        isDeletingAccount = true
        do {
            try await supabaseAuth.deleteAccount()
            isSupabaseSignedIn = false
            friends = []
            clearFriendsCache()
            // Reset local sharing state back to safe defaults (sharing OFF) — otherwise
            // signing in again would immediately re-push these old preferences to the
            // brand-new account on the next settings save, silently resurrecting the very
            // social configuration that was just deleted.
            let defaults = AppSettings()
            settings.socialShareWatchlist = defaults.socialShareWatchlist
            settings.socialShareWatched = defaults.socialShareWatched
            settings.socialDontShare = defaults.socialDontShare
            settings.socialFeaturedItemKeys = defaults.socialFeaturedItemKeys
            settings.socialExcitedForKeys = defaults.socialExcitedForKeys
            saveLocalSoon()
        } catch {
            deleteAccountErrorMessage = error.localizedDescription
        }
        isDeletingAccount = false
    }
}
