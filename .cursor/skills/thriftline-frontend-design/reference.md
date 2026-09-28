# ThriftLine Frontend Design Reference

Rules 4–55. Same authority as `SKILL.md`.

---

# 4. Human-Like Language

Interfaces must speak like a person, not like technical documentation.

Copy should be:

* short
* natural
* specific
* reassuring where appropriate
* action-oriented
* easy to scan

Avoid robotic text such as:

* "Transaction execution successful."
* "Operation failed."
* "Proceed to next process."
* "No data available."
* "Invalid input detected."
* "User authentication unsuccessful."

Prefer natural wording:

* "Payment confirmed"
* "We couldn't complete your payment."
* "Try again"
* "No orders yet"
* "Enter a valid phone number."
* "We couldn't sign you in. Check your details and try again."

Do not expose:

* database language
* API terminology
* RPC names
* internal status codes
* stack traces
* debug messages
* developer terminology

to normal users.

---

# 5. Clear CTAs

Buttons must tell the user what happens next.

Avoid vague actions such as:

* Continue
* Submit
* Confirm
* Proceed
* Okay
* Next

when a more specific action can be used.

Prefer outcome-driven CTAs such as:

* Create listing
* Place bid
* Add address
* Save address
* Pay with GCash
* Mark as shipped
* Confirm delivery
* Report delivery problem
* Send offer
* Apply as seller
* Capture ID
* Use this photo
* Contact rider
* Resolve report

Primary CTA = the most important next action.

Secondary actions must visually compete less.

Dangerous actions must never visually compete with the primary safe action.

---

# 6. Less Is More

Do not present everything at once.

Prioritize information based on:

1. What the user needs now.
2. What helps them make the next decision.
3. What they may need afterward.
4. Optional details.

Use progressive disclosure.

Examples:

Instead of displaying the entire order history on an order card:

Show:

* product
* total
* current status
* next action

Put deeper information inside Order Details.

Instead of displaying every seller statistic on every product card:

Show only the trust information needed to evaluate the seller.

Users should be able to understand a screen within a few seconds.

---

# 7. Spacing Must Communicate Relationships

Spacing should NOT be equal everywhere.

Use spacing to communicate relationships.

Elements belonging together should be closer.

Different groups should have noticeably more separation.

Example:

Title
8px
Supporting text

24px

Next section title

Do not automatically put `16px` between everything.

Recommended spacing system:

* 4px — extremely related details
* 8px — closely related content
* 12px — related component elements
* 16px — normal component spacing
* 20–24px — separate content groups
* 32px — major sections
* 40–48px — major screen transitions when appropriate

Use the system as guidance, not as a requirement to make everything uniform.

Visual hierarchy is more important than mathematical symmetry.

---

# 8. Whitespace Is Functional

Whitespace is not wasted space.

Use whitespace to:

* separate unrelated information
* emphasize primary actions
* make important content easier to find
* prevent cognitive overload
* improve reading
* make transactional screens feel safer

However, do not create excessive empty space that forces unnecessary scrolling.

Mobile whitespace must remain efficient.

---

# 9. Typography

Typography should establish hierarchy before containers do.

Prefer hierarchy through:

* size
* weight
* contrast
* spacing

before introducing another card or divider.

Keep typography levels limited and consistent.

Typical hierarchy:

* Screen title
* Section title
* Primary content
* Supporting content
* Metadata/captions

Avoid using bold text everywhere.

If everything is emphasized, nothing is emphasized.

Body content should remain easy to read.

Use sentence case for interface labels.

Avoid:

`PAYMENT DETAILS`

Prefer:

`Payment details`

unless there is a strong design reason otherwise.

---

# 10. Proximity Law

Things placed close together are perceived as belonging together.

Apply this deliberately.

Example product listing:

Product name
Price

small gap

Seller information

larger gap

Delivery information

Do not separate closely related information with excessive borders or containers.

Grouping can often be achieved with spacing alone.

---

# 11. Jakob's Law

Users expect ThriftLine to behave similarly to applications they already understand.

Do not invent unusual interactions for common actions.

Follow familiar marketplace conventions for:

* search
* cart
* favorites
* checkout
* back navigation
* product galleries
* bidding
* messaging
* order tracking
* profiles
* notifications
* filters
* forms
* bottom navigation

Innovation is useful when it solves a real problem.

Do not make users learn a new interaction simply to make ThriftLine look unique.

Uniqueness should come from product experience and visual identity, not unfamiliar controls.

---

# 12. Hick's Law

More choices create slower decisions.

Reduce visible choices.

When possible:

* show one primary action
* keep secondary actions secondary
* move uncommon options into menus
* group filters
* progressively reveal advanced settings

Do not present eight buttons when users usually need one or two.

When there are many choices, organize them into meaningful groups.

---

# 13. Miller's Law

Avoid overwhelming users with too many pieces of information at once.

Aim for small, meaningful groups.

Prefer around 3–5 primary items when possible.

Avoid presenting more than approximately 7 competing pieces of information in one visual group.

Break larger information sets into:

* sections
* tabs
* steps
* progressive disclosure
* expandable details

---

# 14. Von Restorff Effect

The element that visually stands out is remembered.

Use this carefully.

The strongest visual emphasis should usually belong to:

* primary CTA
* important transaction status
* major warning
* winning/current bid
* important trust state
* payment amount

Do not make several elements compete for maximum attention.

One dominant action is usually enough.

---

# 15. Fitts's Law

Important interactive targets must be easy to tap.

Do not make frequently used actions tiny.

Important buttons should have comfortable tap targets.

Avoid placing dangerous actions immediately beside common actions.

Frequently used controls should be easy to reach, particularly on mobile.

Do not rely on tiny text links for critical actions.

---

# 16. Doherty Threshold

The system should feel responsive.

Provide immediate visual feedback when users:

* tap a button
* submit a form
* place a bid
* add to cart
* send a message
* upload media
* authorize payment
* confirm delivery
* submit a report

If an operation takes time:

* disable duplicate submission
* show relevant progress
* preserve context
* tell the user what is happening

Do not leave the UI appearing frozen.

Avoid fake loading screens when the operation is already complete.

---

# 17. Tesler's Law

Every system has unavoidable complexity.

Do not solve developer complexity by pushing it onto the user.

For example:

Do not ask a buyer to understand payment provider terminology.

Do not ask sellers to understand internal order-state enums.

Do not make users manually perform something the application can determine safely.

Hide technical complexity while preserving important information.

---

# 18. Aesthetic-Usability Effect

A polished interface can feel easier to use, but appearance must never hide poor usability.

Beauty must support:

* hierarchy
* readability
* confidence
* trust
* comprehension

Never sacrifice clarity for aesthetics.

---

# 19. Serial Position Effect

Users remember the beginning and end of sequences more easily.

For multi-step flows:

* clearly explain what is about to happen
* make the current step obvious
* finish with a clear success/result state

Especially apply this to:

* seller verification
* checkout
* ID capture
* payment
* delivery confirmation
* report submission
* listing creation

---

# 20. Feedback and System Status

Users should always understand:

* where they are
* what happened
* what the system is doing
* what they should do next

Every asynchronous interaction needs a state.

Never leave important actions ambiguous.

Examples:

Instead of:

`Loading...`

when context is available, prefer:

`Checking payment...`

or:

`Uploading your ID...`

or:

`Placing your bid...`

Status communication must reflect the actual process.

---

# 21. Instant Errors

Surface errors as soon as they can reasonably be identified.

Errors should appear close to the problem.

For forms:

* validate fields contextually
* explain how to fix the issue
* preserve entered information
* focus or scroll toward invalid content when appropriate

Bad:

`Invalid input`

Better:

`Enter a valid Philippine mobile number starting with 09.`

Bad:

`Failed`

Better:

`Your bid wasn't placed. Refresh the auction and try again.`

Do not rely solely on temporary snackbars for errors requiring user action.

Do not make users hunt for what went wrong.

---

# 22. Prevent Errors Before They Happen

Good UX prevents errors rather than merely reporting them.

Examples:

* disable impossible quantity changes
* prevent bidding below the required amount
* prevent selecting unavailable products
* clearly mark sold items
* warn before destructive actions
* disable duplicate payment submissions
* show accepted upload requirements before camera capture
* clearly explain delivery confirmation consequences

Use confirmation dialogs only when the decision has meaningful consequences.

Do not ask for confirmation for trivial reversible actions.

---

# 23. Loading States

Use the loading pattern appropriate for the action.

Use:

* skeletons when loading structured content
* inline progress for a specific component
* button progress for button-triggered operations
* full-screen loading only when the entire page genuinely cannot function

Do not cover the whole screen with a spinner for every network call.

Do not show developer log overlays.

Prevent accidental duplicate actions while loading.

---

# 24. Empty States

Empty states should help users understand what to do next.

An empty state requires:

1. What is missing.
2. Why the screen is empty when useful.
3. What the user can do next.

Bad:

`No data`

Better:

`No listings yet`

`Create your first listing to start selling on ThriftLine.`

CTA:

`Create listing`

Do not make empty states overly decorative.

Do not add giant illustrations unless they materially improve the experience.

---

# 25. Success States

Successful actions need clear closure.

Tell the user:

* what succeeded
* what happens next

Examples:

`Payment confirmed`

`Your order is now waiting for the seller to prepare it.`

or

`Listing published`

`Buyers can now find it in the marketplace.`

Do not force users to infer whether an operation succeeded.

---

# 26. Interactive Data Cards

When displaying important numbers, add useful visual context.

A number by itself often lacks meaning.

Instead of:

`Orders: 12`

consider:

`12 orders`
`3 need attention`

Instead of displaying five oversized KPI cards, determine which numbers actually matter.

Good data cards may contain:

* primary value
* concise label
* status
* comparison
* progress indicator
* relevant quick action

Cards should be interactive only when tapping them leads somewhere meaningful.

Do not make noninteractive cards look tappable.

---

# 27. Visualize the Numbers

Turn complicated numbers into information users can understand quickly.

Use when useful:

* progress bars
* segmented indicators
* compact trend indicators
* status distribution
* completion indicators
* simple comparisons
* rating summaries

Avoid charts when simple text communicates the information better.

Do not add charts merely to make a dashboard look advanced.

Every visualization must answer a question.

Example:

Instead of making sellers read:

`7 completed / 10 total`

a small completion indicator can immediately communicate progress.

---

# 28. Progress at a Glance

Users should recognize progress without reading paragraphs.

Apply visual status indicators to:

* seller verification
* order fulfillment
* delivery
* listing creation
* reports
* bidding
* account setup
* trust/verification information

Use understandable states.

Example:

Paid → Preparing → Out for delivery → Delivered

The current state should be visually clear.

Completed steps should be distinguishable from upcoming steps.

Never use color as the only indicator.

---

# 29. Compact Data Views

Marketplace interfaces contain large amounts of data.

Display useful information efficiently.

A compact order item might contain:

* thumbnail
* product title
* total
* status
* date
* primary next action

It does not need a large separate container for each value.

Prefer information density with hierarchy over excessive card size.

Admin interfaces may use greater information density than buyer interfaces.

---

# 30. Marketplace Product Cards

Product cards should prioritize:

1. Product image
2. Product name
3. Price/current bid
4. Important state
5. Essential seller/trust information when relevant

Avoid cluttering every product card with:

* descriptions
* addresses
* seller biographies
* multiple ratings
* excessive actions
* several badges

Product cards are for scanning.

Product details belong on the product details screen.

Maintain consistent image dimensions to prevent layout jumping.

ThriftLine imagery should remain relevant to thrift products.

---

# 31. Marketplace Trust

ThriftLine deals with transactions between people.

Trust-related information must be visible without making the application feel frightening.

Important trust information may include:

* verification state
* seller reputation
* transaction status
* ratings
* report status
* payment state

Use calm, factual language.

Do not use threatening wording.

Do not visually shame users with unnecessarily aggressive styling.

Serious restrictions or warnings should still be unmistakable.

---

# 32. Forms

Forms should feel like conversations rather than database forms.

Order fields logically.

Only request information needed at that point.

Use:

* clear labels
* helpful examples where necessary
* correct keyboard type
* appropriate autofill
* inline validation
* sensible defaults
* clear required/optional distinction

Do not rely only on placeholder text as the field label.

Group related fields.

For long forms, divide the process into understandable steps.

---

# 33. Navigation

Navigation should answer:

`Where am I?`

and:

`Where can I go?`

Do not overload bottom navigation.

Use familiar destinations for primary areas.

Secondary functionality belongs inside screens, profiles, contextual menus, or appropriate nested navigation.

Preserve ThriftLine's established navigation behavior unless there is a real usability problem.

Avoid duplicate ways of reaching the same feature unless there is a good reason.

---

# 34. Buyer Experience

Buyer screens should optimize for:

* discovery
* confidence
* comparing products
* buying quickly
* tracking purchases
* contacting sellers
* understanding bids
* finding Looking For requests
* reporting genuine problems

Avoid exposing seller-management functionality while the user is operating in Buyer mode.

Keep purchasing actions obvious.

---

# 35. Seller Experience

Seller screens should optimize for:

* creating listings
* managing inventory
* seeing orders needing attention
* responding to buyers
* fulfilling orders
* managing auctions
* responding to Looking For requests
* monitoring account/verification status

Use strong prioritization.

If three orders need shipping, that information should be easier to notice than historical completed orders.

Actionable work should appear before passive information.

---

# 36. Admin Experience

Admin interfaces should feel professional and operational.

Admin design may be denser than buyer/seller screens because the user is reviewing information rather than shopping.

Prioritize:

* items requiring attention
* status
* identity/context
* evidence
* decisions
* history

Do not create a generic "admin dashboard" simply because the user is an administrator.

Every admin screen must support a real administrative task.

Avoid meaningless dashboard charts.

Use numbers, filters, statuses, compact tables/lists, progress indicators, and charts only when they improve decision-making.

---

# 37. Destructive Actions

Destructive actions include:

* delete
* cancel order
* dismiss report
* restrict account
* remove listing
* reject seller application

They must be visually distinct from primary actions.

Ask for confirmation when the consequence is meaningful and difficult to reverse.

Explain the consequence.

Avoid generic:

`Are you sure?`

Prefer:

`Delete this listing?`

`Buyers will no longer be able to view or purchase it.`

Buttons:

`Keep listing`
`Delete listing`

---

# 38. Icons

Use icons to improve recognition.

Do not use icons merely as decoration.

No emojis in the ThriftLine interface.

Use a consistent icon family.

Do not mix unrelated icon styles.

Icons with unclear meaning should include labels.

Never expect users to guess an unfamiliar icon.

---

# 39. Borders, Radius, and Shadows

Use visual containers only when they help grouping or interaction.

Do not wrap every section in a card.

Use a restrained and consistent border-radius system.

Avoid excessive giant corner radii.

Shadows should communicate elevation, not decoration.

Flat surfaces with spacing and subtle borders are often preferable for information-heavy screens.

---

# 40. Color Usage

ThriftLine teal `#0D9488` is an accent and action color, not wallpaper.

Do not flood every screen with teal.

Use it strategically for:

* important CTAs
* selected navigation
* active states
* branded highlights
* meaningful progress

Maintain enough neutral space so branded elements remain distinctive.

Use semantic colors consistently.

---

# 41. Accessibility

Every implementation must consider accessibility.

Ensure:

* sufficient color contrast
* readable text sizes
* comfortable tap targets
* icons have semantic meaning
* important states are not communicated by color alone
* forms have proper labels
* error messaging is understandable
* content remains usable with increased text size where practical

Do not make secondary text so light that it becomes difficult to read.

Accessibility is part of quality, not an optional polish step.

---

# 42. Responsive Flutter Layout

The frontend must work across realistic Android screen sizes.

Do not build layouts that only work on the current emulator.

Avoid fragile fixed dimensions.

Prefer responsive constraints using Flutter layout tools such as:

* `Expanded`
* `Flexible`
* `LayoutBuilder`
* `MediaQuery`
* appropriate constraints
* scrollable layouts where needed

Handle:

* narrow screens
* long product names
* large text
* keyboard appearance
* safe areas
* bottom navigation
* system insets
* different image aspect ratios

Never accept RenderFlex overflow as a visual compromise.

Fix the layout.

---

# 43. Flutter Component Architecture

When implementing designs:

Prefer reusable components for patterns that genuinely repeat.

Examples:

* product cards
* status chips
* primary buttons
* seller identity rows
* order progress
* empty states
* form fields

Do not create an abstraction for a component used once unless it substantially improves maintainability.

Do not create huge widget files.

Separate meaningful screen sections when doing so improves readability.

Do not refactor unrelated backend or domain logic while performing a frontend task unless required.

---

# 44. Design Tokens

Whenever practical, centralize repeated design decisions.

Examples:

* colors
* spacing
* radius
* typography
* animation durations
* elevations

Do not scatter slightly different values throughout the application:

`15`
`16`
`17`
`18`

without a reason.

Consistency should come from reusable design decisions rather than copying widgets.

---

# 45. Motion and Animation

Animation must communicate something.

Good purposes:

* state change
* navigation
* progress
* selection
* expansion
* confirmation

Avoid:

* unnecessary bouncing
* continuous motion
* decorative movement
* animations that delay actions
* excessively long transitions

Animations should generally feel fast and subtle.

Users should never have to wait for an animation before completing an important transaction.

---

# 46. Interaction Hierarchy

On every screen identify:

### Primary action

What is the most likely or important thing the user should do?

### Secondary action

What useful alternative might they need?

### Tertiary action

What uncommon or low-priority action exists?

Design visual importance in that order.

Do not make all three look equally important.

---

# 47. One Screen, One Main Purpose

Before implementing a screen, be able to complete this sentence:

`The primary purpose of this screen is to ______.`

If several unrelated answers are required, the screen may be overloaded.

Remove, reorganize, or progressively disclose secondary content.

---

# 48. Design Around Decisions

Do not organize screens based on database tables.

Organize them based on decisions users need to make.

For example, an order details page is not a visualization of the `orders` database row.

It should answer:

* What did I order?
* How much did I pay?
* What is happening now?
* Who is involved?
* What should I do next?
* What can I do if something goes wrong?

Design for those questions.

---

# 49. Preserve Context

When users complete or cancel an action, return them somewhere logical.

Examples:

After editing an address:
return to the checkout/address context.

After reporting a delivery:
return to the relevant order with the report status visible.

After payment:
show the payment result and order state.

Avoid unnecessarily returning users to the home screen.

---

# 50. Status Naming

Statuses must be understandable to normal users.

Do not expose internal names such as:

`payment_pending`

Convert them to:

`Payment pending`

Prefer even clearer wording when context permits.

Avoid having multiple labels representing the same underlying state unless the different wording improves contextual understanding.

---

# 51. Trustworthy Transaction Design

For money, bidding, delivery, verification, and reports:

Always clearly show critical information before irreversible actions.

For payments:

* amount
* payment method
* result
* next step

For bids:

* current bid
* minimum acceptable bid
* user's entered bid
* outcome after placing bid

For delivery confirmation:

* order
* delivery status
* consequence of confirmation

For reports:

* person/order being reported
* reason
* evidence
* submission status

Critical transaction UX must prioritize certainty over visual minimalism.

---

# 52. Image Handling

Images should use consistent dimensions and cropping rules.

Use appropriate:

* `BoxFit.cover`
* clipping
* placeholders
* loading states
* error states

Do not allow failed images to destroy the layout.

Do not stretch product images.

Do not let differently sized uploads create inconsistent product cards.

---

# 53. Search and Filters

Search interfaces should prioritize the search task.

Avoid surrounding the search field with unnecessary UI.

Filters should be:

* understandable
* removable
* visibly active
* easy to reset

Do not expose every possible filter simultaneously.

Frequently useful filters should appear before advanced filters.

---

# 54. Notifications and Feedback

Use the correct feedback mechanism.

Use inline feedback when the message belongs to a specific field or component.

Use snackbar/toast feedback for lightweight temporary confirmation.

Use a dialog when the user must make a decision.

Use a full result screen when completing a significant multi-step flow.

Do not use snackbars as the solution for every event.

---

# 55. HCI Review

Every frontend change should be reviewed against:

* visibility of system status
* match between system and real-world language
* user control
* consistency
* error prevention
* recognition over recall
* efficiency
* minimalist design
* useful error recovery
* accessibility

Do not require users to remember information from a previous screen when it can reasonably be displayed again.
