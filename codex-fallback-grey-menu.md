# Codex Prompt: iOS Tab Bar Goes Grey After Sheet Dismissal

## What We Want to Achieve

After any modal sheet is dismissed in a SwiftUI app, the tab bar (UIKit `UITabBar`) temporarily shows a grey/opaque background instead of the expected blur effect. We want the tab bar to always show a clean blur that reflects the content behind it, immediately after dismissal — no grey flash, no delay.

---

## App Architecture

- SwiftUI app, iOS 17+ deployment target
- `ContentView.swift` uses a stock SwiftUI `TabView` (`legacyTabView`) with 4 tabs
- The tab bar is UIKit's native `UITabBar` under the hood
- `TabBarTypographyManager.swift` (static enum, `@MainActor`) owns all tab bar appearance customization
- `TabBarControllerAccessor` (UIViewControllerRepresentable) walks the parent chain to find the `UITabBarController` and calls `reconcile()` on every SwiftUI update

### Key design decision: custom blur

We use `UITabBarAppearance.configureWithTransparentBackground()` to remove UIKit's own blur machinery (`_UIBackdropLayer` inside `_UIBarBackground`). In its place we insert a `UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))` directly into the `UITabBar` view hierarchy.

Rationale: UIKit's internal `_UIBackdropLayer` cannot be reliably forced to re-sample after a modal sheet is dismissed — all public APIs (setNeedsLayout, setNeedsDisplay, isTranslucent toggle, appearance reassignment) failed to make it refresh without a visible flash.

---

## The Bug

After ANY modal `.sheet` dismissal:
- The tab bar background shows grey/opaque for a noticeable duration
- The grey comes from `_UIBarBackground` (UIKit's internal background view inside `UITabBar`) temporarily reverting to an opaque grey state during UIKit's presentation-controller cleanup

UIKit's `_UIBarBackground` sits at subview index 1 (drawn **in front** of our `UIVisualEffectView` which was at index 0). When `configureWithTransparentBackground()` is in effect, `_UIBarBackground` is clear, so our blur shows through. But during sheet dismissal UIKit briefly resets `_UIBarBackground` to grey — hiding our blur.

Every previous fix attempt recreated our `UIVisualEffectView` at index 0, which remained behind the grey `_UIBarBackground`, so none of them had any visible effect.

---

## What We've Tried (All Failed)

1. **setNeedsLayout / layoutIfNeeded** on the tab bar — insufficient, `_UIBackdropLayer` recaptures during display passes, not layout
2. **layer.setNeedsDisplay** — doesn't trigger `_UIBackdropLayer` re-sample on UIKit's private layer
3. **isTranslucent toggle** (false → true) — caused a visible solid-grey flash
4. **UITabBarAppearance reassignment** (forceReconcile with force:true) — caused flashes when approach included blanking the appearance
5. **configureWithTransparentBackground + custom UIVisualEffectView at index 0** — correct concept but wrong z-position; blur hidden behind `_UIBarBackground`
6. **effect = nil → effect = restore in single CATransaction** — CA may batch same-state mutations into a no-op; even when it doesn't, was still at wrong z-index
7. **effect = nil in one dispatch, restore in async dispatch (two frames)** — caused 1-frame transparent flash; still at wrong z-index
8. **Remove UIVisualEffectView + recreate in CATransaction.setDisableActions** — correct recreate mechanism, but still at wrong z-index (index 0)
9. **onDismiss → notification → 3-pass timers (0s/0.55s/1.1s)** — timing guesswork, partially helped but unreliable
10. **.onDisappear on sheet content + 0.4s delayed second pass** — better timing trigger (fires after animation end for simple sheets), but z-index was still wrong

---

## Current Code State

### `FamilyTodo/Utilities/TabBarTypographyManager.swift`

```swift
@MainActor
enum TabBarTypographyManager {

    static func reconcile(
        themeStore: ThemeStore,
        tabBarController: UITabBarController? = nil,
        selectedIndex: Int? = nil,
        force: Bool = false
    ) {
        guard let tabBarController else { return }
        insertCustomBlurIfNeeded(in: tabBarController)
        tabBarController.tabBar.backgroundColor = .clear   // ← added
        
        // ... appearance match check (early return if no repair needed) ...
        
        updateLiveTabBar(...)
    }

    static func insertCustomBlurIfNeeded(in tabBarController: UITabBarController) {
        let tabBar = tabBarController.tabBar

        let blur: UIVisualEffectView
        if let existing = tabBar.viewWithTag(customBlurViewTag) as? UIVisualEffectView {
            blur = existing
        } else {
            let newBlur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
            newBlur.tag = customBlurViewTag
            newBlur.translatesAutoresizingMaskIntoConstraints = false
            tabBar.addSubview(newBlur)
            NSLayoutConstraint.activate([...fill constraints...])
            blur = newBlur
        }

        positionBlurAboveBackground(blur, in: tabBar)
    }

    // Positions blur above UIKit's internal background (all non-UIControl views),
    // below the interactive tab buttons (UIControl subviews).
    private static func positionBlurAboveBackground(
        _ blur: UIVisualEffectView,
        in tabBar: UITabBar
    ) {
        let others = tabBar.subviews.filter { $0 !== blur }
        let targetIndex = others.firstIndex(where: { $0 is UIControl }) ?? min(1, others.count)
        tabBar.insertSubview(blur, at: targetIndex)
    }

    static func forceBlurRefresh(tabBarController: UITabBarController?) {
        guard let tabBarController else { return }
        let tabBar = tabBarController.tabBar

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        tabBar.viewWithTag(customBlurViewTag)?.removeFromSuperview()
        tabBar.backgroundColor = .clear

        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        blur.tag = customBlurViewTag
        blur.translatesAutoresizingMaskIntoConstraints = false

        let targetIndex = tabBar.subviews.firstIndex(where: { $0 is UIControl }) ?? tabBar.subviews.count
        tabBar.insertSubview(blur, at: targetIndex)

        NSLayoutConstraint.activate([...fill constraints...])
        CATransaction.commit()
    }

    private static func makeAppearance(style: ResolvedTabBarStyle) -> UITabBarAppearance {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.shadowColor = .separator
        // ... sets icon/title colors for all layout appearances ...
        return appearance
    }

    private static func updateLiveTabBar(...) {
        tabBar.standardAppearance = standardAppearance
        // iOS 15+: tabBar.scrollEdgeAppearance = scrollEdgeAppearance
        tabBar.tintColor = selectedColor
        tabBar.unselectedItemTintColor = normalColor
        tabBar.backgroundColor = .clear   // ← added
        // repairSelection(...)
    }
}
```

### `FamilyTodo/ContentView.swift` (relevant parts)

```swift
// Notification posted from .onDisappear on each sheet's content view
.onReceive(NotificationCenter.default.publisher(for: .tabBarAppearanceRefreshRequested)) { _ in
    refreshTabBarAppearanceForHouseholdChromeChange()
}

private func refreshTabBarAppearanceForHouseholdChromeChange() {
    let controller = tabBarController
    TabBarTypographyManager.forceBlurRefresh(tabBarController: controller)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
        TabBarTypographyManager.forceBlurRefresh(tabBarController: controller)
    }
}
```

### Sheet sites (example pattern)

```swift
// HouseholdSettingsView.swift
.sheet(item: $householdBeingEdited) { household in
    NavigationStack {
        EditHouseholdView(household: household).id(household.id)
    }
    .onDisappear { handleHouseholdEditDismiss() }
}

// handleHouseholdEditDismiss posts .tabBarAppearanceRefreshRequested via DispatchQueue.main.async
```

---

## Problem Symptoms Still Observed (latest build)

After the z-position fix (`positionBlurAboveBackground`), the bug is **still present**. The behaviour is unchanged:
- "Recently Purchased" sheet dismissal: smallest grey effect
- Edit Household / Invite Member / Bundle Editor dismissal: same grey as before the fix

---

## What We Need Help With

We need to understand:

1. **Why is the grey still happening** after positioning our `UIVisualEffectView` above `_UIBarBackground`? If our blur is now in front of `_UIBarBackground`, the grey from `_UIBarBackground` should be irrelevant.

2. **Is there a reliable way to detect and hook into the exact moment** UIKit finishes its presentation-controller cleanup (after sheet dismissal), without polling with timers?

3. **Is there a fundamentally different architecture** that would make the blur immune to UIKit's sheet presentation/dismissal side-effects? Options considered but not tried:
   - Placing the `UIVisualEffectView` as a **sibling** of the `UITabBar` (in the tab bar controller's view, not inside the tab bar), positioned to cover the tab bar area
   - Using a `CADisplayLink` to continuously check and refresh the blur for ~0.5s after dismissal
   - Going back to `configureWithDefaultBackground()` (UIKit's native blur) but finding a private/undocumented API or category extension that forces `_UIBackdropLayer` to re-sample

4. **What does UIKit's `UITabBar` view hierarchy actually look like** at the moment the grey appears, and which view is the source of the grey?

---

## Constraints

- iOS 17.0 minimum deployment target
- No private APIs in production code
- No third-party dependencies
- Must work with all 4 themes: System (light/dark), Retro Dark, Retro Light, Paper
- Visual parity with the current blur look must be preserved
- No visible flash or animation during the fix
