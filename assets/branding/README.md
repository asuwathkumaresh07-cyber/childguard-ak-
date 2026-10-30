# Family Guard logo family

## Current supplied logos (1.0.5)

The user supplied `child_logo.jpeg` and `parent_logo.jpeg`. The built-in imagegen
tool extracted transparent marks from these files, preserving the designs and
colors. App copies: `apps/child/assets/branding/child-logo.png` and
`apps/parent/assets/branding/parent-logo.png`. `apply-logos.ps1` sizes those final
marks for Android launcher masks without cropping. Original JPEGs are retained.

Edit prompts: Child — remove the pale rounded-square and white background,
preserve the teal/blue enclosing hands, golden child and sparkle, keep the full
mark with transparent padding. Parent — remove all baked-in gray checkerboard,
preserve the glossy blue shield, silver parent/child and gold orbit/sparkles,
keep the full mark with transparent padding. Both requested true alpha PNG.

The notes below describe the earlier logo family, which is superseded by the
new supplied child and parent marks.

Generated with the built-in imagegen tool. Company is the master brand; Parent and Child each carry the shared shield/family/heart emblem. No text is baked into the app icons.

## Files
- company-logo.png: master company logo (1024 x 1024).
- parent-logo.png: parent app logo (1024 x 1024).
- child-logo.png: child app logo (1024 x 1024).
- logo-family-preview.png: labeled overview.

App-local copies live in apps/parent/assets/branding and apps/child/assets/branding. Android launcher icons include five density sizes and an inset adaptive icon for Android 8+. The sign-in screens use the corresponding app logo. Existing APK installers must be rebuilt to include these assets.

## Generation prompts

Company: Create one polished square company app icon for Family Guard, a family wellbeing and digital safety brand. No text. A distinctive bold soft-edged deep teal shield containing a white heart formed by two embracing curved shapes, with one small warm coral circular accent at the upper right of the heart suggesting a family member. Premium flat vector-like graphic, optically balanced, friendly and reassuring, very simple silhouette legible at 48 pixels. Solid warm white background filling entire square, mark occupies central 65%, generous safety margins for Android icon masking. No gradients, shadows, mockups, lettering, border or presentation sheet. This is the master company logo whose shield-heart emblem will also appear in the parent and child app icons.

Parent (company image supplied as reference): Create the PARENT companion app icon for the attached Family Guard company logo. One square icon, no text. Same polished friendly flat vector-like style and deep teal / white / coral palette. Main symbol: a large warm reassuring adult bust silhouette in deep teal with round head and curved protective shoulders; at center of chest place a clearly recognizable miniature of the EXACT attached company shield-heart-family emblem, retaining the two white family figures and coral dot. The company emblem must be an obvious shared brand badge, occupying around 35% of icon width. Adult silhouette and badge together occupy central 65% of square with generous white margins for Android masking. Solid white full square background. Simple bold shapes readable at small sizes. No letters, typography, photo, shadow, borders or mockup.

Child (company image supplied as reference): Create the CHILD companion app icon for the attached Family Guard company logo. One square icon, no text. Same polished friendly flat vector-like style and deep teal / white / coral palette. Main symbol: a cheerful child bust, round coral face with very simple teal smiling eyes and smile, small playful teal hair tuft, rounded coral shoulders. At center of chest place a clearly recognizable miniature of the EXACT attached company shield-heart-family emblem, retaining the two white family figures and coral dot. Shared company badge is obvious, about 35% icon width. Child and badge together fit central 65% square with generous white safety margins for Android masking. Solid white full square background. Premium clean simple bold shapes readable at small sizes. Avoid lettering, gradients, shadow, border, mockups or presentation sheet.
