+++
title = "Installation"
weight = 12
+++
The following steps are here to help you initialize your new workshop. If you don't know Hugo at all, we strongly suggest you learn more about it by following this [great documentation for beginners](https://gohugo.io/overview/quickstart/).

## Create your project

If you haven't already, make a copy of this entire directory and rename it something descriptive, similar to the title of your workshop.

```bash
cp -R Aws-workshop-template/ my-first-worshop/
```

## What's Included

This project the following folders:

* `deck`: The location to store your presentation materials, if not already stored centrally in a system like KnowledgeMine or Wisdom.
* `resources`: Store any example code, IAM policies, or Cloudformation templates needed by your workshop here.
* `workshop`: This is the core workshop folder. This is generated as HTML and hosted for presentation for customers.


## Navigate to the `workshop` directory

All command line directions in this documentation assume you are in the `workshop` directory. Navigate there now, if you aren't there already.

```bash
cd my-first-workshop/workshop
```

## Create your first chapter page

Chapters are pages that contain other child pages. It has a special layout style and usually just contains a _brief abstract_ of the section.

```markdown
Discover what this template is all about and the core concepts behind it.
```

renders as 

{{< img "chapter.en.png" "A Chapter" >}}

This template provides archetypes to create skeletons for your workshop. Begin by creating your first chapter page with the following command

```bash
hugo new --kind chapter intro/_index.md
```

By opening the given file, you should see the property `chapter=true` on top, meaning this page is a _chapter_.

By default all chapters and pages are created as a draft. If you want to render these pages, remove the property `draft: true` from the front matter section.

## Create your first content pages

Then, create content pages inside the previously created chapter. Here are two ways to create content in the chapter:

```bash
hugo new intro/first-content.md
hugo new intro/second-content/_index.md
```

Feel free to edit those files by adding some sample content and replacing the `title` value in the beginning of the files. 

## Launching the website locally

Launch by using the following command:

```bash
hugo serve
```

Go to `http://localhost:1313`

You should notice three things:

1. You have a left-side **Intro** menu, containing two submenus with names equal to the `title` properties in the previously created files.
2. The home page explains how to customize it by following the instructions.
3. When you run `hugo serve`, when the contents of the files change, the page automatically refreshes with the changes. Neat!

Alternatively, you can run the following command in a terminal window to tell Hugo to automatically rebuild whenever a file is changed. This can be helpful when rapidly iterating over content changes.

```bash
hugo serve -D
```

## Build the website

When your site is ready to deploy, run the following command:

```bash
hugo
```

A `public` folder will be generated, containing all static content and assets for your website. It can now be deployed on any web server.

{{% notice note %}}
Do not deploy this content in your own Isengard account. Please contact the Event Outfitters team when you are ready to publish and we will assist with deployment to a custom url similar to https://my-aws-workshop.immersionday.com/
{{% /notice %}}
