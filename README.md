## Posterous to Markdown Export

The goal is to have a script that exports an entire Posterous blog to disk, formatted in such a way to easily drop into the <code>_posts</code> folder of popular static site generators such as Octopress. This [Tumblr to Markdown script](https://gist.github.com/1632061) is an example of similar functionality.

### Goals

* "just works" on Mac OS X
* edit file or pass in username / API tokens on the command line
* output all posts as individual Markdown-formatted text files
* support for categories
* download and locally store Posterous-hosted images