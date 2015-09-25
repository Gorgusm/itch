
app = require "app"
path = require "path"
fs = require "fs"

request = require "request"
progress = require "request-progress"
fstream = require "fstream"

keyMirror = require "keymirror"

fileutils = require "./fileutils"
api = require "./api"

AppDispatcher = require "./dispatcher/AppDispatcher"
AppConstants = require "./constants/AppConstants"
AppActions = require "./actions/AppActions"
AppStore = require "./stores/AppStore"

items = []

InstallState = keyMirror {
  PENDING: null
  SEARCHING_UPLOAD: null
  DOWNLOADING: null
  EXTRACTING: null
  CONFIGURING: null
  RUNNING: null
}

class AppInstall
  @library_dir: path.join(app.getPath("home"), "Downloads", "itch.io")
  @archives_dir: path.join(@library_dir, "archives")
  @apps_dir: path.join(@library_dir, "apps")

  constructor: (opts) ->
    @game = opts.game
    user = @game.user.username
    slug = @game.url.match /[^\/]+$/
    @app_path = path.join(AppInstall.apps_dir, "#{slug} by #{user}")
    @state = InstallState.PENDING
    @start()

  start: ->
    @search_for_uploads()

  search_for_uploads: ->
    @state = InstallState.SEARCHING_UPLOAD

    client = AppStore.get_current_user()
    call = if @game.key
      client.download_key_uploads @game.key.id
    else
      client.game_uploads @game.id

    call.then (res) =>
      { uploads } = res
      console.log "Got uploads:\n#{JSON.stringify(uploads)}"

      # filter uploads to find one relevant to our current platform
      prop = switch process.platform
        when "darwin" then "p_osx"
        when "win32" then "p_windows"
        when "linux" then "p_linux"

      interesting_uploads = uploads.filter (upload) -> !!upload[prop]

      if interesting_uploads.length
        # TODO let user choose
        @set_upload interesting_uploads[0]
      else
        AppActions.notify "No uploads found for #{@game.title}"

  set_upload: (@upload) ->
    console.log "Choosing to download #{@upload.filename}"

    ext = fileutils.ext @upload.filename
    archive_name = "upload-#{@upload.id}#{ext}"
    @archive_path = path.join(AppInstall.archives_dir, archive_name)
    @get_url()

  get_url: ->
    @state = InstallState.DOWNLOADING

    client = AppStore.get_current_user()
    call = if @game.key
      client.download_upload_with_key @game.key.id, @upload.id
    else
      client.download_upload @upload.id

    call.then (res) =>
      @url = res.url
      @download()

  download: ->
    @state = InstallState.DOWNLOADING

    if fs.existsSync @archive_path
      @extract()
      return

    r = progress request.get(@url), throttle: 25
    r.on 'response', (response) =>
      console.log "Got status code: #{response.statusCode}"
      contentLength = response.headers['content-length']
      console.log "Got content length: #{contentLength}"

    r.on 'progress', (state) =>
      AppActions.set_progress(0.01 * state.percent)

    dst = fstream.Writer(path: @archive_path)
    r.pipe(dst).on 'close', =>
      AppActions.clear_progress()
      AppActions.bounce()
      AppActions.notify "#{@game.title} finished downloading."
      @extract()

  extract: ->
    @state = InstallState.EXTRACTING
    require("./extractor").extract(@archive_path, @app_path).then(=>
      @configure()
    ).catch (e) =>
      AppActions.notify "Failed to extract / configure / launch #{@game.title}"
      throw e

  configure: ->
    @state = InstallState.CONFIGURING
    require("./configurator").configure(@app_path).then((res) =>
      @executables = res.executables
      console.log "Configuration successful"
      @launch()
    )

  launch: ->
    @state = InstallState.RUNNING
    require("./launcher").launch(@executables[0])

install = ->
  AppDispatcher.register (action) ->
    switch action.action_type
      when AppConstants.DOWNLOAD_QUEUE
        items.push new AppInstall(action.opts)

module.exports = { install }

