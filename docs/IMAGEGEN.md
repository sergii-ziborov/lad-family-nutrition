# Снимки открытых демо-рецептов

Шесть изображений созданы встроенным ImageGen без использования фотографий из присланной книги в качестве референсов. Каждый снимок генерировался отдельным запросом. Файлы находятся в `Assets.xcassets` и используются только для открытых демо-рецептов.

Общая часть запроса (на английском):

> Use case: photorealistic-natural. Asset type: original food photograph for an iPhone family recipe card. Scene/backdrop: warm neutral tabletop, pale linen and simple ceramic tableware; no people. Style/medium: photorealistic natural editorial food photography, believable home-cooked food textures. Composition/framing: one plated dish filling most of a square frame, three-quarter overhead view, suitable for cropping in a mobile card. Lighting/mood: soft window daylight, inviting but not overly staged. Constraints: match a calm warm editorial recipe-app aesthetic; no cookbook page, no text, no logos, no labels, no watermark, no collage.

Отдельная часть `Primary request` для каждого снимка:

| Рецепт | Запрос |
| --- | --- |
| Овсянка с бананом | Creamy oatmeal porridge topped with freshly sliced banana in a simple speckled ceramic breakfast bowl. |
| Яйца с томатами и тостом | Two softly cooked eggs with warm chopped tomatoes, served with one slice of toasted bread on a simple ceramic plate. |
| Курица с гречкой и огурцом | Tender cooked chicken pieces beside fluffy buckwheat and sliced fresh cucumber on one ceramic lunch plate. |
| Паста с томатами и кабачком | Short pasta with tomato and zucchini pieces, lightly finished with grated cheese, in a shallow ceramic bowl. |
| Индейка с рисом и овощами | Tender turkey pieces with rice, carrots and zucchini on one ceramic dinner plate. |
| Чечевица с овощами | Hearty red lentil stew with tomatoes, sweet pepper and onion in a simple ceramic bowl. |

Перед публикацией снимки нужно проверить на совпадение с реальным приготовленным блюдом и ингредиентами: генерация может создавать несуществующие детали.

## Расширение завтраков — 21 октября 2026

Использован встроенный image_gen, по одному отдельному изображению на рецепт. Файлы скопированы в `Assets.xcassets/Breakfast-<recipe-id>.imageset/image.png`; исходные генерации сохранены. Это иллюстрации блюда, а не изображение точно взвешенной порции.

Общий запрос: `Use case: photorealistic-natural. Asset: square recipe photograph for a family meal planning app. Warm daylight, realistic home cooking, matte cream ceramic dishes on pale beige linen, close three-quarter overhead framing, natural textures, restrained Mediterranean food editorial photography. One modest serving centered and visible. No extra ingredients, text, labels, watermark or people.`

| Recipe ID / asset | Primary subject |
| --- | --- |
| bf-savory-oat-pancake / `Breakfast-bf-savory-oat-pancake` | One savory oat pancake folded in half, filled with cottage cheese and fresh tomato slices; oats, egg, cottage cheese, tomatoes and a little olive oil only. |
| bf-buckwheat-egg-mushrooms / `Breakfast-bf-buckwheat-egg-mushrooms` | Cooked buckwheat, sautéed mushrooms, wilted spinach, one fully hard-boiled egg cut in halves and a spoon of plain yogurt. |
| bf-overnight-apple-oats / `Breakfast-bf-overnight-apple-oats` | Overnight oats mixed with Greek yogurt and milk, topped with apple cubes, a small portion of walnuts and cinnamon; no honey or syrup. |
| bf-baked-curd-oats / `Breakfast-bf-baked-curd-oats` | Individual baked oats with cottage cheese and apple cubes, lightly golden surface, egg blended into the oats; no visible fried egg, honey or syrup. |
| bf-curd-herb-toast / `Breakfast-bf-curd-herb-toast` | Two wholegrain toasts with cottage cheese, chopped dill and cucumber; a little olive oil in the cheese; no egg or avocado. |
| bf-chickpea-egg-skillet / `Breakfast-bf-chickpea-egg-skillet` | Chickpeas, sautéed tomatoes, wilted spinach and one fully cooked egg with firm yolk in a small skillet, a small wholegrain toast beside it. |
| bf-red-lentil-pancakes / `Breakfast-bf-red-lentil-pancakes` | Three small red-lentil pancakes, yogurt with parsley and cucumber slices; no eggs, bread or syrup. |
| bf-mozzarella-egg-toast / `Breakfast-bf-mozzarella-egg-toast` | Two wholegrain toasts baked with egg, melted mozzarella and tomatoes; fully cooked egg, no avocado or meat. |
| bf-millet-pumpkin-yogurt / `Breakfast-bf-millet-pumpkin-yogurt` | Yellow millet porridge with pumpkin cubes, Greek yogurt and a small portion of walnuts; no honey or syrup. |
| bf-salmon-avocado-toast / `Breakfast-bf-salmon-avocado-toast` | Two wholegrain toasts with mashed avocado and flakes of fully baked salmon, cucumber beside them; no raw or smoked fish, no egg. |


## Default-course expansion, 25 October 2026

29 separate food illustrations were generated with the built-in imagegen tool, without third-party reference images. Final originals are in the ignored workspace folder `catalog-authoring/images/`; each is linked to a recipe ID in `catalog-authoring/image-provenance-20261025.jsonl`. The prompt set is `catalog-authoring/image-prompts-20261025.json`. Owner-only JPEG exports in `../Lad-private/course-images/Expansion-<recipe-id>.jpg` are at most 1280 pixels and below the API size limit. Three contact sheets were inspected for recipe correspondence. The images are illustrative, not measurements of a cooked portion. Output provenance does not establish exclusive copyright or clear rights in the source course.

## Independent editorial edition, 26 October 2026

The old `Pancakes` picture did not have a generation record in the available audit. A new original illustration was generated with the built-in imagegen tool from ingredient facts only, without a reference photo. The selected original is `catalog-authoring/images/pancakes-original-20261026.png`; the app uses `Assets.xcassets/Pancakes.imageset/pancakes.png`. The exact prompt, generation path and SHA-256 are in `catalog-authoring/image-provenance-20261026.json`. The superseded file remains in the owner's private pre-edit snapshot. Visual inspection confirmed cottage-cheese pancakes and berries without extra toppings.

`catalog-authoring/course-image-inventory-20261026.json` resolves the 150 current dish images to existing files and records 150 distinct file hashes. Earlier generation logs are provenance evidence; different hashes do not prove copyright ownership or worldwide visual uniqueness. No source-book page or photograph was added to the app by this edit.
