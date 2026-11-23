# App Review notes — Ladlekin 1.0.0 (6)

Draft for the owner to paste into App Store Connect after completing the release checklist. Supply a real review contact and current support/privacy URLs before submission.

Ladlekin is an iPhone family meal planner and a personal food/weight journal. The name under the icon is Ladlekin. Store name: Ladlekin: Family Meal Planner. Subtitle: One meal, different portions. Russian subtitle: Одна кухня, разные порции. This release has a free public catalogue and bundled offline content. No login, pilot key or payment information is needed for the 50-dish free menu. A non-consumable purchase unlocks the 150-dish Healthy eating course and removes ads. Use Restore purchases with the same Apple Account. Paid creator courses and author royalties are a future programme and are not launched; the app’s own full-course purchase is separate from future creator royalties.

## Suggested review flow

1. Open Today and select a family member. A plan is a suggestion; no meal is automatically recorded as eaten.
2. Open Catalogue → Courses → Healthy eating; inspect recipes, ingredient quantities, illustrated steps and expandable nutrient details. A country picker on a recipe sets approximate ingredient prices for Israel, Ukraine or the United States. Own prices take priority.
3. Open Products and an ingredient to see its image, descriptions and storage guidance. Package prices may be entered by the user or use optional statistical references for Israel, Ukraine and the United States. Reference periods and categories are shown; these are not live shop quotations. Own prices take priority.
4. Record actual food/portions from Today; review Diary, reports and CSV in settings. Sharing is optional and uses the system share sheet.
5. Open Family → Weight and trends. Record a measurement, change the period, edit/delete an entry or export CSV. A fresh install has no invented weight history.
6. Open settings → About for Terms, Privacy, For course authors, Sources/support, and Library licenses. Switch language to English, Russian or Ukrainian to check the translated documents.
7. Disable network access: bundled recipes and local personal records remain usable. Optional reminders can be declined.

## Health and data

Ladlekin does not diagnose or treat conditions, guarantee weight loss, recommend supplements or automatically prescribe an energy deficit. Adult profile-based portions are opt-in; the adult energy formula is not used for children/pregnancy/breastfeeding/therapeutic contexts. Nutrition values are ingredient/reference estimates; check actual labels, substitutions and food safety.

No HealthKit and no cross-app tracking. The free catalogue may show non-personalized AdMob banners after the required consent flow; a purchase removes them. The ad SDK receives no diary, body measurements, allergies or dietary goals. Personal health data stays on the device in this Release configuration; CloudKit personal synchronisation and pilot-key access are disabled. Catalogue requests contain no personal health profile. CSV export is explicitly chosen by the user. Older pilot cloud records are not automatically erased.

The weight chart is an observational journal: no predictions, weight-loss goal or claimed medical interpretation. Recipe and ingredient pictures illustrate the dish. They are not a photo of the user’s plate and not a health analysis. One course, Healthy eating, is selected by default and can be turned off. Meal times default to breakfast 10:00, lunch 14:00 and dinner 19:00. After that time a dish moves to the eaten section; the checkmark stays the user’s.

The legal pages use Apple's Standard EULA for the App Store app licence. Check the final publisher/support identity and contact URLs against the listing. The app has no remote account registration/deletion flow in this release; records can be edited/deleted locally, with optional manual export.

For the current internal beta, ads are disabled. Google's documented sample app
identifier satisfies the SDK's startup metadata requirement, the banner ID is
empty, and the Release code refuses to start advertising with that sample ID.
App measurement is delayed until explicit SDK initialization. Publisher IDs
must replace the sample before App Store publication.


## Owner readiness notes

This is a draft for future review. The owner describes mixed input origins (personal material, internet, books and AI contributions). New wording and illustrations do not establish exclusive rights or prove that every input was licensed. Do not present this edition as an authorised reproduction of a third-party course, or claim formal trademark clearance. Review any remaining protected material, contractual restrictions and required attribution before publication. The price API, revised 150-dish manifest and current illustrations were deployed on 2026-10-29, with separate Production and Sandbox routes. The USD 3 non-consumable and EN/RU/UK localizations are configured in App Store Connect. Checkout remains disabled until a dedicated purchase key is installed and a real Sandbox transaction is verified. Ad configuration and public support/privacy contacts still need completion.
