#' Render Dockerized R Markdown Documents
#'
#' @description
#' Render dockerized R Markdown documents using Docker containers.
#'
#' @details
#' Before using this function, please run \code{\link{lift}} on the
#' RMD document first to generate the \code{Dockerfile}.
#'
#' After a successful rendering, you will be able to clean up the
#' Docker image with \code{\link{purge_image}}.
#'
#' Please see \code{vignette('liftr-intro')} for details of the extended
#' YAML metadata format and system requirements for rendering dockerized
#' R Markdown documents.
#'
#' @param input Input file to render in Docker container.
#' @param tag Docker image name to build, sent as docker argument \code{-t}.
#' If not specified, it will use the same name as the input file.
#' @param build_args A character string specifying additional
#' \code{docker build} arguments. For example,
#' \code{--pull=true -m="1024m" --memory-swap="-1"}.
#' @param container_name Docker container name to run.
#' If not specified, will use a randomly generated name.
#' @param cache Logical. Controls the \code{--no-cache} argument
#' in \code{docker run}. Setting this to be \code{TRUE} can accelerate
#' the rendering speed substantially for repeated/interactive rendering
#' since the Docker image layers will be cached, with only the changed
#' (knitr related) image layer being updated. Default is \code{TRUE}.
#' @param purge_info Logical. Should we write the Docker container and
#' image information to a YAML file for purging later?
#' Default is \code{TRUE}.
#' @param ... Additional arguments passed to
#' \code{\link[rmarkdown]{render}}.
#'
#' @return
#' \itemize{
#' \item A list containing the image name, container name,
#' and Docker commands will be returned.
#' \item An YAML file ending with \code{.docker.yml} storing the
#' image name, container name, and Docker commands for rendering
#' this document will be written to the directory of the input file.
#' \item The rendered output will be written to the directory of the
#' input file.
#' }
#'
#' @export render_docker
#'
#' @importFrom rmarkdown render
#' @importFrom yaml as.yaml
#'
#' @examples
## Included in \dontrun{} since users need Docker installed to run them.
#' # copy example file
#' dir_example = paste0(tempdir(), '/liftr-tidyverse/')
#' dir.create(dir_example)
#' file.copy(system.file("examples/liftr-tidyverse.Rmd", package = "liftr"), dir_example)
#'
#' # containerization
#' input = paste0(dir_example, "liftr-tidyverse.Rmd")
#' lift(input)
#'
#' \dontrun{
#' # render the document with Docker
#' render_docker(input)
#'
#' # view rendered document
#' browseURL(paste0(dir_example, "liftr-tidyverse.pdf"))
#'
#' # purge the generated Docker image
#' purge_image(paste0(dir_example, "liftr-tidyverse.docker.yml"))}

render_docker = function(
  input = NULL,
  tag = NULL, build_args = NULL, container_name = NULL,
  cache = TRUE, purge_info = TRUE, ...) {

  if (is.null(input))
    stop('missing input file')
  if (!file.exists(normalizePath(input)))
    stop('input file does not exist')

  # docker build
  dockerfile_path = paste0(file_dir(input), '/Dockerfile')

  if (!file.exists(dockerfile_path))
    stop('Cannot find Dockerfile in the same directory of input file,
         please dockerize the R Markdown document via lift() first.')

  if (Sys.which('docker') == '')
    stop('Cannot find `docker` on system search path,
         please ensure we can use `docker` from shell')

  image_name = ifelse(is.null(tag), file_name_sans(input), tag)
  cache = paste0("--no-cache=", ifelse(cache, "false", "true"))
  docker_build_cmd = paste0(
    "docker build ", cache, " --rm=true ",
    build_args, " -t=\"", image_name, "\" ",
    file_dir(dockerfile_path))

  # docker run
  container_name = ifelse(
    is.null(container_name),
    paste0('liftr_container_', uuid()),
    container_name)

  docker_run_cmd_base = paste0(
    "docker run --rm --name \"", container_name,
    "\" -u `id -u $USER` -v \"",
    file_dir(dockerfile_path), ":", "/liftrroot/\" ",
    image_name,
    " Rscript -e \"library('knitr');library('rmarkdown');",
    "library('shiny');setwd('/liftrroot/');")

  # process additional arguments passed to rmarkdown::render()
  dots_arg = list(...)

  if (length(dots_arg) == 0L) {

    docker_run_cmd = paste0(
      docker_run_cmd_base, "render(input = '",
      file_name(input), "')\"")

  } else {

    if (!is.null(dots_arg$input))
      stop('input can only be specified once')

    if (!is.null(dots_arg$output_file) |
        !is.null(dots_arg$output_dir) |
        !is.null(dots_arg$intermediates_dir)) {
      stop('`output_file`, `output_dir`, and `intermediates_dir`
           are not supported to be changed now, we will consider
           this in the next versions.')
    }

    dots_arg$input = file_name(input)
    tmp = tempfile()
    dput(dots_arg, file = tmp)
    render_args = paste0(readLines(tmp), collapse = '\n')
    render_cmd = paste0("do.call(render, ", render_args, ')')

    docker_run_cmd = paste0(docker_run_cmd_base, render_cmd, "\"")

    }

  # output container and image info before rendering
  res = list(
    'container_name'   = container_name,
    'image_name'       = image_name,
    'docker_build_cmd' = docker_build_cmd,
    'docker_run_cmd'   = docker_run_cmd)

  if (purge_info) {
    writeLines(as.yaml(res), con = paste0(
      file_dir(input), '/', file_name_sans(input), '.docker.yml'))
  }

  # render
  system(docker_build_cmd)
  system(docker_run_cmd)

  res

  }

#' @rdname render_docker
#' @export drender
drender = function(...) {
  .Deprecated('render_docker')
}
