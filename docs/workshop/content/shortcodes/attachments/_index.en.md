+++
title = "Attachments"
description = "The Attachments shortcode displays a list of files attached to a page."
weight = 31
+++

The Attachments shortcode displays a list of files attached to a page.

{{% attachments /%}}

## Usage

The shortcurt lists files found in a **specific folder**.

Attachements must be place in a **folder** named like your page and ending with **.files**.

> * content
>   * chapter
>      * _index.en.md
>      * _index.en.files
>          * attachment.pdf

{{% notice note %}}
Be aware that if you use a multilingual website, you will need to have as many folders as languages.
{{% /notice %}}

### Parameters

| Parameter | Default | Description |
|:--|:--|:--|
| title | "Attachments" | List's title  |
| style | "" | Choose between "orange", "grey", "blue" and "green" for nice style |
| pattern | ".*" | A regular expressions, used to filter the attachments by file name. <br/><br/>The **pattern** parameter value must be [regular expressions](https://en.wikipedia.org/wiki/Regular_expression).

For example:

* To match a file suffix of 'jpg', use **.*jpg** (not *.jpg).
* To match file names ending in 'jpg' or 'png', use **.*(jpg|png)**

### Examples

#### List of attachments ending in pdf or mp4


    {{%/*attachments title="Related files" pattern=".*(png|mp4)"/*/%}}

renders as

{{%attachments title="Related files" pattern=".*(png|mp4)"/%}}

#### Colored styled box

    {{%/*attachments style="orange" /*/%}}

renders as

{{% attachments style="orange" /%}}


    {{%/*attachments style="grey" /*/%}}

renders as 

{{% attachments style="grey" /%}}

    {{%/*attachments style="blue" /*/%}}

renders as

{{% attachments style="blue" /%}}
    
    {{%/*attachments style="green" /*/%}}

renders as

{{% attachments style="green" /%}}