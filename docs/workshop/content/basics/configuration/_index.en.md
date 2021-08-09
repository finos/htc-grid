+++
title = "Configuration"
weight = 13
+++

## Global site parameters

On top of [Hugo global configuration](https://gohugo.io/overview/configuration/), this template lets you define the following parameters in your `config.toml` (here, values are default).

Note that some of these parameters are explained in details in other sections of this documentation.

```toml
[params]
  # Prefix URL to edit current page. Will display an "Edit this page" button on top right hand corner of every page. 
  # This is only relevant if you're open-sourcing your source markdown on Github; by default we provide you with 
  # a private CodeCommit repo so you do not need or want to expose an EditURL:
  editURL = ""
  # Author of the site, will be used in meta information
  author = ""
  # Description of the site, will be used in meta information
  description = ""
  # Shows a checkmark for visited pages on the menu
  showVisitedLinks = false
  # Disable search function. It will hide search bar
  disableSearch = false
  # Javascript and CSS cache are automatically busted when new version of site is generated. 
  # Set this to true to disable this behavior (some proxies don't handle well this optimization)
  disableAssetsBusting = false
  # Set this to true to disable copy-to-clipboard button for inline code.
  disableInlineCopyToClipBoard = false
  # A title for shortcuts in menu is set by default. Set this to true to disable it. 
  disableShortcutsTitle = false
  # When using mulitlingual website, disable the switch language button.
  disableLanguageSwitchingButton = false
  # Hide breadcrumbs in the header and only show the current page title
  disableBreadcrumb = true
  # Hide Next and Previous page buttons normally displayed full height beside content
  disableNextPrev = true
  # Order sections in menu by "weight" or "title". Default to "weight"
  ordersectionsby = "weight"
```

## Activate search

If not already present, add the follow lines in the same `config.toml` file.

```toml
[outputs]
home = [ "HTML", "RSS", "JSON"]
```

{{% notice note %}}
When using this functionality, Hugo generates an index.json file at the root of public folder to be consumed by the lunr.js javascript search enginge. 
When you build the site with `hugo serve`, Hugo generates the file internally and it doesn’t show up in the filesystem
{{% /notice %}}