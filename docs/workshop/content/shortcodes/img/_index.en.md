+++
title = "Image"
description = "Displays a preformatted image on your page"
weight = 35
+++

The img shortcode displays a preformatted image that is stored in your [Page Bundle](https://gohugo.io/content-management/page-bundles/) on your page. This means you should store your images in the same directory as your page. In the example below, the page markdown and the "chapter.en.png" file are both stored in the same directory.

## Usage

This shortcode takes two parameters:  

* The relative path to the image (based on the location of the current page).
* The alternate text to be used with the image.  

```markdown
{{</* img "chapter.en.png" "A Chapter" */>}}
```

{{< img "chapter.en.png" "A Chapter" >}}
