+++
title = "Archetypes"
chapter = false
weight = 22
+++

Using the command: `hugo new [relative new content path]`, you can start a content file with the date and title automatically set. While this is a welcome feature, active writers need more : [archetypes](https://gohugo.io/content/archetypes/).

It is pre-configured skeleton pages with default front matter. Please refer to the documentation for types of page to understand the differences.

## Chapter {#archetypes-chapter}

To create a Chapter page, run the following commands

```bash
hugo new --kind chapter <name>/_index.en.md
```

It will create a page with predefined Front-Matter:

```markdown
+++
title = "{{ replace .Name "-" " " | title }}"
date = {{ .Date }}
weight = 5
chapter = true
pre = "<b>X. </b>"
+++

Lorem Ipsum.
```

## Default

To create a default page, run either one of the following commands

```bash
# Either
hugo new <chapter>/<name>/_index.en.md
# Or
hugo new <chapter>/<name>.en.md
```

It will create a page with predefined Front-Matter:

```markdown
+++
title = "{{ replace .Name "-" " " | title }}"
date = {{ .Date }}
weight = 5
+++

Lorem Ipsum.
```