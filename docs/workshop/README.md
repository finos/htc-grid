## HTC-Grid Workshop

Contains the content to drive users through a guided workshop. The content in this folder uses [https://gohugo.io/] structure to deliver the HTC-Grid Workshop static site.

## Building the Workshop site

### Local Build
To build the content:
 * clone this repository
 * [install hugo](https://gohugo.io/getting-started/installing/). The website is currently running on Hugo 0.74.3  https://github.com/gohugoio/hugo/releases/download/v0.74.3/hugo_0.74.3_Linux-64bit.tar.gz
 * The project uses [hugo learn](https://github.com/matcornic/hugo-theme-learn/) template as a git submodule. To update the content, execute the following code
```bash
pushd themes/learn
git submodule init
git submodule update --checkout --recursive
popd
```
 * Run hugo to generate the site, and point your browser to http://localhost:1313
```bash
hugo serve -D
```

### Containerized Development

The image can also serve as a development environment using [docker-compose](https://docs.docker.com/compose/). The following command will spin up a container exposing the website at [localhost:1313](http://localhost:1313) and mount `config.toml` and the directories `./content`, `./layouts` and `./static`, so that local changes will automatically be picked up by the development container.

```
$ docker-compose up -d  ## To see the logs just drop '-d'
Starting ec2-spot-workshops_hugo_1 ... done
```
