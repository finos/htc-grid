+++
title = "Multilingual and i18n"
weight = 25
+++

This template is fully compatible with Hugo multilingual mode.

It provides:

- Translation strings for default values (English and French). Feel free to contribute !
- Automatic menu generation from multilingual content
- In-browser language switching

<img src="/en/cont/i18n/i18n.en.png?classes=shadow" alt="I18n menu" />

## Basic configuration

After learning [how Hugo handle multilingual websites](https://gohugo.io/content-management/multilingual), define your languages in your `config.toml` file.

For example with current French and English website.

```toml
# English is the default language
defaultContentLanguage = "en"
# Force to have /en/my-page and /fr/my-page routes, even for default language.
defaultContentLanguageInSubdir= true

[Languages]
[Languages.en]
title = "Documentation for Hugo Learn Theme"
weight = 1
languageName = "English"

[Languages.fr]
title = "Documentation du thème Hugo Learn"
weight = 2
languageName = "Français"
```

Then, for each new page, append the *id* of the language to the file.

- Single file `my-page.md` is split in two files:
    - in English: `my-page.en.md`
    - in French: `my-page.fr.md`
- Single file `_index.md` is split in two files:
    - in English: `_index.en.md`
    - in French: `_index.fr.md`

{{% notice info %}}
Be aware that only translated pages are displayed in menu. It's not replaced with default language content.
{{% /notice %}}

{{% notice tip %}}
Use [slug](https://gohugo.io/content-management/multilingual/#translate-your-content) Front Matter parameter to translate urls too.
{{% /notice %}}

## Overwrite translation strings

Translations strings are used for common default values used in the theme (*Edit this page* button, *Search placeholder* and so on). Translations are available in french and english but you may use another language or want to override default values.

To override these values, create a new file in your local i18n folder `i18n/<idlanguage>.toml` and inspire yourself from the theme `themes/learn/i18n/en.toml` 

## Disable language switching

Switching the language in the browser is a great feature, but for some reasons you may want to disable it. 

Just set `disableLanguageSwitchingButton=true` in your `config.toml`

```toml
[params]
  # When using mulitlingual website, disable the switch language button.
  disableLanguageSwitchingButton = true
```