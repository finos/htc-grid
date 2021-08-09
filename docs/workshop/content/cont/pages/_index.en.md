+++
title = "Pages Organization"
weight = 21
+++

In **Hugo**, pages are the core of your site. All of your workshop steps should be developed as pages.

## Folders

Organize your workshop similar to the steps within a specfic workshop. For example, a workshop with 3 labs might look like this:

```markdown
    content
    ├── lab-1
    │   ├── step-1
    │   │   ├── step-1a
    │   │   │   ├── _index.en.md    <-- /en/lab-1/step-1/step-1a.html (in English)
    │   │   │   └── _index.fr.md    <-- /fr/lab-1/step-1/step-1a.html (in French)
    │   │   ├── _index.en.md        <-- /en/lab-1/step-1.html (in English)
    │   │   └── _index.fr.md        <-- /fr/lab-1/step-1.html (in French)
    │   ├── _index.en.md            <-- /en/lab-1.html (in English)
    │   └── _index.fr.md            <-- /fr/lab-1.html (in French)
    ├── _index.en.md                <-- /en/ (in English)
    └── _index.fr.md                <-- /fr/ (in French)
```

{{% notice note %}}
`_index.en.md` is required in each folder, it’s your “folder home page”
{{% /notice %}}

## Types

This template defines two types of pages. *Default* and *Chapter*. Both can be used at any level of the workshop, the only difference being layout display.

A **Chapter** displays a page meant to be used as introduction for a set of child pages. Commonly, it contains a simple title and a catch line to define content that can be found under it.
You can define any HTML as prefix for the menu. In the example below, it's just a number but that could be an [icon](https://fortawesome.github.io/Font-Awesome/).

{{< img "pages-chapter.en.png" "Chapter page" >}}

```markdown
+++
title = "Basics"
chapter = true
weight = 10
pre = "<b>1. </b>"
+++

### Chapter 1

# Basics

Discover what this template is all about and the core-concepts behind it.
```

To tell the template to consider a page as a chapter, set `chapter=true` in the Front Matter of the page.

A **Default** page is any other content page.

{{< img "pages-default.en.png" "Default page" >}}

```toml
+++
title = "Installation"
weight = 12
+++
```

## Images

There are multiple ways to store images you need to use as part of your workshop. These pages use the Page Bundle method, which keeps the images for specific pages in the same folder structure as the content.

```markdown
    content
    └── lab-1
        └── step-1
            └── step-1a
                ├── _index.en.md        <-- /en/lab-1/step-1/step-1a.html
                └── my_image.en.png    <-- /fr/lab-1/step-1/step-1a/my_image.en.png
```

You can reference images in your pages when using the [Page Bundle](https://gohugo.io/content-management/page-bundles/) method by using the `img` shortcode. More information can be found here.

You can also opt to store all of your images in the `static` folder, which will be accessible from {{% siteurl %}}

```markdown
    content
    └── lab-1
        └── step-1
            └── step-1a
                ├── _index.en.md    <-- /en/lab-1/step-1/step-1a.html
    static
    └── images
        └── my_image.en.png         <-- /images/my_image.en.png
```

You can reference images stored in the `static` folder by using [markdown syntax for images](/en/cont/markdown.html#images).

## Front Matter configuration

Each Hugo page has to define a [Front Matter](https://gohugo.io/content/front-matter/) in *yaml*, *toml* or *json*.

This template uses the following parameters on top of Hugo ones :

```toml
+++
# Table of content (toc) is enabled by default. Set this parameter to true to disable it.
# Note: Toc is always disabled for chapter pages
disableToc = "false"
# If set, this will be used for the page's menu entry (instead of the `title` attribute)
menuTitle = ""
# The title of the page in menu will be prefixed by this HTML content
pre = ""
# The title of the page in menu will be postfixed by this HTML content
post = ""
# Set the page as a chapter, changing the way it's displayed
chapter = false
# Hide a menu entry by setting this to true
hidden = false
# Display name of this page modifier. If set, it will be displayed in the footer.
LastModifierDisplayName = ""
# Email of this page modifier. If set with LastModifierDisplayName, it will be displayed in the footer
LastModifierEmail = ""
+++
```

### Ordering sibling menu/page entries

This template provides a [flexible way](https://gohugo.io/content/ordering/) to handle order for your pages.

The simplest way is to set `weight` parameter to a number.

```toml
+++
title = "My page"
weight = 5
+++
```

We recommend that you set the weight for chapters as multiple of 10, with the pages inside each chapter counting down from there. For example:

Chapter 1: `weight = 10`  
Page 1: `weight = 11`  
Page 2: `weight = 12`  

Chapter 2: `weight = 20`  
Page 1: `weight = 21`  

### Using a custom title for menu entries

By default, the template will use a page's `title` attribute for the menu item (or `linkTitle` if defined).

But a page's title has to be descriptive on its own while the menu is a hierarchy.
We've added the `menuTitle` parameter for that purpose:

For example (for a page named `content/install/linux.md`):

```toml
+++
title = "Install on Linux"
menuTitle = "Linux"
+++
```
