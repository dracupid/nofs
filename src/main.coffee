###*
 * I hate to reinvent the wheel. But to purely use promise, I don't
 * have many choices.
###
Overview = 'nofs'

npath = require 'path'
_ = require './utils'

###*
 * Here I use [Bluebird][Bluebird] only as an ES6 shim for Promise.
 * No APIs other than ES6 spec will be used. In the
 * future it will be removed.
 * [Bluebird]: https://github.com/petkaantonov/bluebird
###
Promise = _.Promise

# nofs won't pollute the native fs.
fs = require 'fs'
nofs = _.extend {}, fs

# Evil of Node.
_.extend nofs, require('graceful-fs')

# Promisify fs.
for k of nofs
	if k.slice(-4) == 'Sync'
		name = k[0...-4]
		pname = name + 'P'
		continue if nofs[pname]
		nofs[pname] = _.promisify nofs[name]

_.extend nofs, {

	###*
	 * Copy an empty directory.
	 * @param  {String} src
	 * @param  {String} dest
	 * @param  {Object} opts
	 * ```coffee
	 * {
	 * 	isForce: false
	 * 	mode: auto
	 * }
	 * ```
	 * @return {Promise}
	###
	copyDirP: (src, dest, opts) ->
		_.defaults opts, {
			isForce: false
		}

		copy = ->
			if opts.isForce
				nofs.rmdirP(dest).catch (err) ->
					if err.code != 'ENOENT'
						Promise.reject err
				.then ->
					nofs.mkdirP dest, opts.mode
			else
				nofs.mkdirP dest, opts.mode

		if opts.mode
			copy()
		else
			nofs.statP(src).then ({ mode }) ->
				opts.mode = mode
				copy()

	###*
	 * See `copyDirP`.
	###
	copyDirSync: (src, dest, opts) ->
		_.defaults opts, {
			isForce: false
		}

		copy = ->
			if opts.isForce
				try
					nofs.rmdirSync dest
				catch err
					if err.code != 'ENOENT'
						throw err

				nofs.mkdirSync dest, opts.mode
			else
				nofs.mkdirSync dest, opts.mode

		if opts.mode
			copy()
		else
			{ mode } = nofs.statSync(src)
			opts.mode = mode
			copy()

	###*
	 * Copy a single file.
	 * @param  {String} src
	 * @param  {String} dest
	 * @param  {Object} opts
	 * ```coffee
	 * {
	 * 	isForce: false
	 * 	mode: auto
	 * }
	 * ```
	 * @return {Promise}
	###
	copyFileP: (src, dest, opts) ->
		_.defaults opts, {
			isForce: false
		}

		copyFile = ->
			new Promise (resolve, reject) ->
				try
					sDest = nofs.createWriteStream dest, opts
					sSrc = nofs.createReadStream src
				catch err
					reject err
				sSrc.on 'error', reject
				sDest.on 'error', reject
				sDest.on 'close', resolve
				sSrc.pipe sDest

		copy = ->
			if opts.isForce
				nofs.unlinkP(dest).catch (err) ->
					if err.code != 'ENOENT'
						Promise.reject err
				.then ->
					copyFile()
			else
				copyFile()

		if opts.mode
			copy()
		else
			nofs.statP(src).then ({ mode }) ->
				opts.mode = mode
				copy()

	###*
	 * See `copyDirP`.
	###
	copyFileSync: (src, dest, opts) ->
		_.defaults opts, {
			isForce: false
		}
		bufLen = 64 * 1024
		buf = new Buffer(bufLen)

		copyFile = ->
			fdr = nofs.openSync src, 'r'
			fdw = nofs.openSync dest, 'w', opts.mode
			bytesRead = 1
			pos = 0

			while bytesRead > 0
				bytesRead = nofs.readSync fdr, buf, 0, bufLen, pos
				nofs.writeSync fdw, buf, 0, bytesRead
				pos += bytesRead

			nofs.closeSync fdr
			nofs.closeSync fdw

		copy = ->
			if opts.isForce
				try
					nofs.unlinkSync dest
				catch err
					if err.code != 'ENOENT'
						throw err
				copyFile()
			else
				copyFile()

		if opts.mode
			copy()
		else
			{ mode } = nofs.statSync src
			opts.mode = mode
			copy()

	###*
	 * Like `cp -r`.
	 * @param  {String} from Source path.
	 * @param  {String} to Destination path.
	 * @param  {Object} opts Extends the options of `eachDir`.
	 * But the `isCacheStats` is fixed with `true`.
	 * Defaults:
	 * ```coffee
	 * {
	 * 	# Overwrite file if exists.
	 * 	isForce: false
	 * }
	 * ```
	 * @return {Promise}
	###
	copyP: (from, to, opts = {}) ->
		_.defaults opts, {
			isForce: false
		}

		flags = if opts.isForce then 'w' else 'wx'

		copy = (src, dest, { isDir, stats }) ->
			opts = {
				isForce: opts.isForce
				mode: stats.mode
			}
			if isDir
				nofs.copyDirP src, dest, opts
			else
				nofs.copyFileP src, dest, opts

		nofs.statP(from).then (stats) ->
			isDir = stats.isDirectory()
			if isDir
				nofs.dirExistsP(to).then (exists) ->
					if exists
						to = npath.join to, npath.basename(from)
					else
						nofs.mkdirsP npath.dirname(to)
				.then ->
					nofs.mapDirP from, to, opts, copy
			else
				copy from, to, { isDir, stats }

	###*
	 * See `copyP`.
	###
	copySync: (from, to, opts = {}) ->
		_.defaults opts, {
			isForce: false
		}

		flags = if opts.isForce then 'w' else 'wx'

		copy = (src, dest, { isDir, stats }) ->
			opts = {
				isForce: opts.isForce
				mode: stats.mode
			}
			if isDir
				nofs.copyDirSync src, dest, opts
			else
				nofs.copyFileSync src, dest, opts

		stats = nofs.statSync from
		isDir = stats.isDirectory()
		if isDir
			if nofs.dirExistsSync to
				to = npath.join to, npath.basename(from)
			else
				nofs.mkdirsSync npath.dirname(to)

			nofs.mapDirSync from, to, opts, copy
		else
			copy from, to, { isDir, stats }

	###*
	 * Check if a path exists, and if it is a directory.
	 * @param  {String}  path
	 * @return {Promise} Resolves a boolean value.
	###
	dirExistsP: (path) ->
		nofs.statP(path).then (stats) ->
			stats.isDirectory()
		.catch -> false

	###*
	 * Check if a path exists, and if it is a directory.
	 * @param  {String}  path
	 * @return {boolean}
	###
	dirExistsSync: (path) ->
		if nofs.existsSync(path)
			nofs.statSync(path).isDirectory()
		else
			false

	###*
	 * Walk through a path recursively with a callback. The callback
	 * can return a Promise to continue the sequence. The resolving order
	 * is also recursive, a directory path resolves after all its children
	 * are resolved.
	 * @param  {String} spath The path may point to a directory or a file.
	 * @param  {Object}   opts Optional. Defaults:
	 * ```coffee
	 * {
	 * 	# Include entries whose names begin with a dot (.).
	 * 	all: false
	 *
	 * 	# To filter paths. It can also be a RegExp or a glob pattern string.
	 * 	# When it's a string, it extends the Minimatch's options.
	 * 	filter: (fileInfo) -> true
	 *
	 * 	# The current working directory to search.
	 * 	cwd: ''
	 *
	 * 	# Whether to include the root directory or not.
	 * 	isIncludeRoot: true
	 *
	 * 	# Whehter to follow symbol links or not.
	 * 	isFollowLink: true
	 *
	 * 	# Iterate children first, then parent folder.
	 * 	isReverse: false
	 *
	 * 	# When isReverse is false, it will be the previous fn resolve value.
	 * 	val: any
	 *
	 * 	# If it return false, sub-entries won't be searched.
	 * 	# When the `filter` option returns false, its children will
	 * 	# still be itered. But when `searchFilter` returns false, children
	 * 	# won't be itered by the fn.
	 * 	searchFilter: (fileInfo) -> true
	 * }
	 * ```
	 * @param  {Function} fn `(fileInfo) -> Promise | Any`.
	 * The `fileInfo` object has these properties: `{ path, isDir, children, stats }`.
	 * Assume the `fn` is `(f) -> f`, the directory object array may look like:
	 * ```coffee
	 * {
	 * 	path: 'dir/path'
	 * 	name: 'path'
	 * 	isDir: true
	 * 	val: 'test'
	 * 	children: [
	 * 		{ path: 'dir/path/a.txt', name: 'a.txt', isDir: false, stats: { ... } }
	 * 		{ path: 'dir/path/b.txt', name: 'b.txt', isDir: false, stats: { ... } }
	 * 	]
	 * 	stats: {
	 * 		size: 527
	 * 		atime: Mon, 10 Oct 2011 23:24:11 GMT
	 * 		mtime: Mon, 10 Oct 2011 23:24:11 GMT
	 * 		ctime: Mon, 10 Oct 2011 23:24:11 GMT
	 * 		...
	 * 	}
	 * }
	 * ```
	 * The `stats` is a native `nofs.Stats` object.
	 * @return {Promise} Resolves a directory tree object.
	 * @example
	 * ```coffee
	 * # Print all file and directory names, and the modification time.
	 * nofs.eachDirP 'dir/path', (obj, stats) ->
	 * 	console.log obj.path, stats.mtime
	 *
	 * # Print path name list.
	 * nofs.eachDirP 'dir/path', (curr) -> curr
	 * .then (tree) ->
	 * 	console.log tree
	 *
	 * # Find all js files.
	 * nofs.eachDirP 'dir/path', {
	 * 	filter: '**\/*.js', nocase: true
	 * }, ({ path }) ->
	 * 	console.log paths
	 *
	 * # Find all js files.
	 * nofs.eachDirP 'dir/path', { filter: /\.js$/ }, ({ path }) ->
	 * 	console.log paths
	 *
	 * # Custom filter
	 * nofs.eachDirP 'dir/path', {
	 * 	filter: ({ path, stats }) ->
	 * 		path.slice(-1) != '/' and stats.size > 1000
	 * }, (path) ->
	 * 	console.log path
	 * ```
	###
	eachDirP: (spath, opts, fn) ->
		if _.isFunction opts
			fn = opts
			opts = {}

		_.defaults opts, {
			all: false
			filter: -> true
			searchFilter: -> true
			cwd: ''
			isIncludeRoot: true
			isFollowLink: true
			isReverse: false
		}

		if _.isRegExp opts.filter
			reg = opts.filter
			opts.filter = (fileInfo) -> reg.test fileInfo.path

		if _.isString opts.filter
			pattern = opts.filter
			opts.filter = (fileInfo) ->
				nofs.minimatch fileInfo.path, pattern

		stat = if opts.isFollowLink then nofs.lstatP else nofs.statP

		resolve = (path) -> npath.join opts.cwd, path

		execFn = (fileInfo) ->
			if not opts.all and fileInfo.name[0] == '.'
				return

			fn fileInfo if opts.filter fileInfo

		decideNext = (dir, name) ->
			path = npath.join dir, name

			stat(resolve path).then (stats) ->
				isDir = stats.isDirectory()
				fileInfo = { path, name, isDir, stats }
				if isDir
					return if not opts.searchFilter fileInfo

					if opts.isReverse
						readdir(path).then (children) ->
							fileInfo.children = children
							execFn fileInfo
					else
						p = execFn fileInfo
						p = Promise.resolve(p) if not p or not p.then
						p.then (val) ->
							readdir(path).then (children) ->
								fileInfo.children = children
								fileInfo.val = val
								fileInfo
				else
					execFn fileInfo

		readdir = (dir) ->
			nofs.readdirP(resolve dir).then (names) ->
				Promise.all names.map (name) ->
					decideNext dir, name

		if opts.isIncludeRoot
			decideNext npath.dirname(spath), npath.basename(spath)
		else
			readdir spath

	###*
	 * See `eachDirP`.
	 * @return {Object | Array} A tree data structure that
	 * represents the files recursively.
	###
	eachDirSync: (spath, opts, fn) ->
		if _.isFunction opts
			fn = opts
			opts = {}

		_.defaults opts, {
			all: false
			filter: -> true
			searchFilter: -> true
			cwd: ''
			isIncludeRoot: true
			isFollowLink: true
			isReverse: false
		}

		if _.isRegExp opts.filter
			reg = opts.filter
			opts.filter = (fileInfo) -> reg.test fileInfo.path

		if _.isString opts.filter
			pattern = opts.filter
			opts.filter = (fileInfo) ->
				nofs.minimatch fileInfo.path, pattern

		stat = if opts.isFollowLink then nofs.lstatSync else nofs.statSync

		resolve = (path) -> npath.join opts.cwd, path

		execFn = (fileInfo) ->
			if not opts.all and fileInfo.name[0] == '.'
				return

			fn fileInfo if opts.filter fileInfo

		decideNext = (dir, name) ->
			path = npath.join dir, name

			stats = stat(resolve path)
			isDir = stats.isDirectory()
			fileInfo = { path, name, isDir, stats }
			if isDir
				return if not opts.searchFilter fileInfo

				if opts.isReverse
					children = readdir(path)
					fileInfo.children = children
					execFn fileInfo
				else
					val = execFn fileInfo
					children = readdir(path)
					fileInfo.children = children
					fileInfo.val = val
					fileInfo
			else
				execFn fileInfo

		readdir = (dir) ->
			names = nofs.readdirSync(resolve dir)
			names.map (name) ->
				decideNext dir, name

		if opts.isIncludeRoot
			decideNext npath.dirname(spath), npath.basename(spath)
		else
			readdir spath

	# Feel pity for Node again.
	# The `nofs.exists` api doesn't fulfil the node callback standard.
	existsP: (path) ->
		new Promise (resolve) ->
			nofs.exists path, (exists) ->
				resolve exists

	###*
	 * Check if a path exists, and if it is a file.
	 * @param  {String}  path
	 * @return {Promise} Resolves a boolean value.
	###
	fileExistsP: (path) ->
		nofs.statP(path).then (stats) ->
			stats.isFile()
		.catch -> false

	###*
	 * Check if a path exists, and if it is a file.
	 * @param  {String}  path
	 * @return {boolean}
	###
	fileExistsSync: (path) ->
		if nofs.existsSync path
			nofs.statSync(path).isFile()
		else
			false

	###*
	 * Get files by patterns.
	 * @param  {String | Array} pattern The minimatch pattern.
	 * @param {Object} opts Extends the options of `eachDir`.
	 * But the `filter` property will be fixed with the pattern.
	 * @param {Function} fn `(fileInfo, list) -> Promise | Any`.
	 * It will be called after each match. By default it is:
	 * `(fileInfo, list) -> list.push fileInfo.path`
	 * @return {Promise} Resolves the list array.
	 * @example
	 * ```coffee
	 * # Get all js files.
	 * nofs.globP('**\/*.js').then (paths) ->
	 * 	console.log paths
	 *
	 * # Custom the iterator. Append '/' to each directory path.
	 * nofs.globP('**\/*.js', (info, list) ->
	 * 	list.push if info.isDir
	 * 		info.path + '/'
	 * 	else
	 * 		info.path
	 * ).then (paths) ->
	 * 	console.log paths
	 * ```
	###
	globP: (patterns, opts = {}, fn) ->
		if _.isFunction opts
			fn = opts
			opts = {}

		if _.isString patterns
			patterns = [patterns]

		list = []

		fn ?= (fileInfo, list) -> list.push fileInfo.path

		getDirPath = (dir) ->
			nofs.dirExistsP(dir).then (exists) ->
				if exists
					dir
				else
					getDirPath npath.dirname(dir)

		cleanPrefix = (pattern) ->
			pattern.replace /^!/, ''

		glob = (pattern) ->
			getDirPath(cleanPrefix pattern).then (dir) ->
				subOpts = _.defaults {
					filter: pattern
				}, opts
				nofs.eachDirP dir, subOpts, (fileInfo) ->
					fn fileInfo, list

		Promise.all patterns.map glob
		.then -> list

	###*
	 * See `globP`.
	 * @return {Array} The list array.
	###
	globSync: (patterns, opts = {}, fn) ->
		if _.isFunction opts
			fn = opts
			opts = {}

		if _.isString patterns
			patterns = [patterns]

		list = []

		fn ?= (fileInfo, list) -> list.push fileInfo.path

		getDirPath = (dir) ->
			if nofs.dirExistsSync dir
				dir
			else
				getDirPath npath.dirname(dir)

		cleanPrefix = (pattern) ->
			pattern.replace /^!/, ''

		glob = (pattern) ->
			dir = getDirPath(cleanPrefix pattern)
			subOpts = _.defaults {
				filter: pattern
			}, opts
			nofs.eachDirSync dir, subOpts, (fileInfo) ->
				fn fileInfo, list

		patterns.map glob

		list

	###*
	 * Map file from a directory to another recursively with a
	 * callback.
	 * @param  {String}   from The root directory to start with.
	 * @param  {String}   to This directory can be a non-exists path.
	 * @param  {Object}   opts Extends the options of `eachDir`. But `cwd` is
	 * fixed with the same as the `from` parameter.
	 * @param  {Function} fn `(src, dest, fileInfo) -> Promise | Any` The callback
	 * will be called with each path. The callback can return a `Promise` to
	 * keep the async sequence go on.
	 * @return {Promise} Resolves a tree object.
	 * @example
	 * ```coffee
	 * # Copy and add license header for each files
	 * # from a folder to another.
	 * nofs.mapDirP(
	 * 	'from'
	 * 	'to'
	 * 	{ isCacheStats: true }
	 * 	(src, dest, fileInfo) ->
	 * 		return if fileInfo.isDir
	 * 		nofs.readFileP(src).then (buf) ->
	 * 			buf += 'License MIT\n' + buf
	 * 			nofs.writeFileP dest, buf
	 * )
	 * ```
	###
	mapDirP: (from, to, opts = {}, fn) ->
		if _.isFunction opts
			fn = opts
			opts = {}

		opts.cwd = from

		nofs.eachDirP '', opts, (fileInfo) ->
			src = npath.join from, fileInfo.path
			dest = npath.join to, fileInfo.path
			fn src, dest, fileInfo

	###*
	 * See `mapDirP`.
	 * @return {Object | Array} A tree object.
	###
	mapDirSync: (from, to, opts = {}, fn) ->
		if _.isFunction opts
			fn = opts
			opts = {}

		opts.cwd = from

		nofs.eachDirSync '', opts, (fileInfo) ->
			src = npath.join from, fileInfo.path
			dest = npath.join to, fileInfo.path
			fn src, dest, fileInfo

	###*
	 * The `minimatch` lib.
	 * [Documentation](https://github.com/isaacs/minimatch)
	 * [Offline Documentation](?gotoDoc=minimatch/readme.md)
	 * @type {Funtion}
	###
	minimatch: require 'minimatch'

	###*
	 * Recursively create directory path, like `mkdir -p`.
	 * @param  {String} path
	 * @param  {String} mode Defaults: `0o777 & ~process.umask()`
	 * @return {Promise}
	###
	mkdirsP: (path, mode = 0o777 & ~process.umask()) ->
		makedir = (path) ->
			nofs.dirExistsP(path).then (exists) ->
				if exists
					Promise.resolve()
				else
					parentPath = npath.dirname path
					makedir(parentPath).then ->
						nofs.mkdirP path, mode
		makedir path

	###*
	 * See `mkdirsP`.
	###
	mkdirsSync: (path, mode = 0o777 & ~process.umask()) ->
		makedir = (path) ->
			if not nofs.dirExistsSync path
				parentPath = npath.dirname path
				makedir parentPath
				nofs.mkdirSync path, mode
		makedir path

	###*
	 * Moves a file or directory. Also works between partitions.
	 * Behaves like the Unix `mv`.
	 * @param  {String} from Source path.
	 * @param  {String} to   Destination path.
	 * @param  {Object} opts Extends the options of `eachDir`.
	 * But the `isCacheStats` is fixed with `true`.
	 * Defaults:
	 * ```coffee
	 * {
	 * 	isForce: false
	 * }
	 * ```
	 * @return {Promise} It will resolve a boolean value which indicates
	 * whether this action is taken between two partitions.
	###
	moveP: (from, to, opts = {}) ->
		_.defaults opts, {
			isForce: false
		}

		opts.isCacheStats = true

		moveFile = (src, dest) ->
			if opts.isForce
				nofs.renameP src, dest
			else
				nofs.linkP(src, dest).then ->
					nofs.unlinkP src

		nofs.statP(from).then (stats) ->
			if stats.isDirectory()
				nofs.dirExistsP(to).then (exists) ->
					if exists
						to = npath.join to, npath.basename(from)
					else
						nofs.mkdirsP npath.dirname(to)
				.then ->
					nofs.renameP from, to
			else
				moveFile from, to
		.catch (err) ->
			if err.code == 'EXDEV'
				nofs.copyP from, to, opts
				.then ->
					nofs.removeP from
			else
				Promise.reject err

	###*
	 * See `moveP`.
	###
	moveSync: (from, to, opts = {}) ->
		_.defaults opts, {
			isForce: false
		}

		opts.isCacheStats = true

		moveFile = (src, dest) ->
			if opts.isForce
				nofs.renameSync src, dest
			else
				nofs.linkSync(src, dest).then ->
					nofs.unlinkSync src

		stats = nofs.statSync(from)
		try
			if stats.isDirectory()
				if nofs.dirExistsSync to
					to = npath.join to, npath.basename(from)
				else
					nofs.mkdirsSync npath.dirname(to)
				nofs.renameSync from, to
			else
				moveFile from, to
		catch err
			if err.code == 'EXDEV'
				nofs.copySync from, to, opts
				nofs.removeSync from
			else
				throw err

	###*
	 * Almost the same as `writeFile`, except that if its parent
	 * directories do not exist, they will be created.
	 * @param  {String} path
	 * @param  {String | Buffer} data
	 * @param  {String | Object} opts Same with the `nofs.writeFile`.
	 * @return {Promise}
	###
	outputFileP: (path, data, opts = {}) ->
		nofs.fileExistsP(path).then (exists) ->
			if exists
				nofs.writeFileP path, data, opts
			else
				dir = npath.dirname path
				nofs.mkdirsP(dir, opts.mode).then ->
					nofs.writeFileP path, data, opts

	###*
	 * See `outputFileP`.
	###
	outputFileSync: (path, data, opts = {}) ->
		if nofs.fileExistsSync path
			nofs.writeFileSync path, data, opts
		else
			dir = npath.dirname path
			nofs.mkdirsSync dir, opts.mode
			nofs.writeFileSync path, data, opts

	###*
	 * Write a object to a file, if its parent directory doesn't
	 * exists, it will be created.
	 * @param  {String} path
	 * @param  {Any} obj  The data object to save.
	 * @param  {Object | String} opts Extends the options of `outputFileP`.
	 * Defaults:
	 * ```coffee
	 * {
	 * 	replacer: null
	 * 	space: null
	 * }
	 * ```
	 * @return {Promise}
	###
	outputJsonP: (path, obj, opts = {}) ->
		if _.isString opts
			opts = { encoding: opts }

		try
			str = JSON.stringify obj, opts.replacer, opts.space
		catch err
			return Promise.reject err

		nofs.outputFileP path, str, opts

	###*
	 * See `outputJSONP`.
	###
	outputJsonSync: (path, obj, opts = {}) ->
		if _.isString opts
			opts = { encoding: opts }

		str = JSON.stringify obj, opts.replacer, opts.space
		nofs.outputFileSync path, str, opts

	###*
	 * Read directory recursively.
	 * @param {String} root
	 * @param {Object} opts Extends the options of `eachDir`. Defaults:
	 * ```coffee
	 * {
	 * 	# Don't include the root directory.
	 * 	isIncludeRoot: false
	 *
	 * 	isCacheStats: false
	 * }
	 * ```
	 * If `isCacheStats` is set true, the returned list array
	 * will have an extra property `statsCache`, it is something like:
	 * ```coffee
	 * {
	 * 	'path/to/entity': {
	 * 		dev: 16777220
	 * 		mode: 33188
	 * 		...
	 * 	}
	 * }
	 * ```
	 * The key is the entity path, the value is the `nofs.Stats` object.
	 * @return {Promise} Resolves an path array. Every directory path will ends
	 * with `/` (Unix) or `\` (Windows).
	 * @example
	 * ```coffee
	 * # Basic
	 * nofs.readDirsP 'dir/path'
	 * .then (paths) ->
	 * 	console.log paths # output => ['dir/path/a', 'dir/path/b/c']
	 *
	 * # Same with the above, but cwd is changed.
	 * nofs.readDirsP 'path', { cwd: 'dir' }
	 * .then (paths) ->
	 * 	console.log paths # output => ['path/a', 'path/b/c']
	 *
	 * # CacheStats
	 * nofs.readDirsP 'dir/path', { isCacheStats: true }
	 * .then (paths) ->
	 * 	console.log paths.statsCache['path/a']
	 * ```
	###
	readDirsP: (root, opts = {}) ->
		_.defaults opts, {
			isCacheStats: false
			isIncludeRoot: false
		}

		list = []
		statsCache = {}
		Object.defineProperty list, 'statsCache', {
			value: statsCache
			enumerable: false
		}

		nofs.eachDirP root, opts, (fileInfo) ->
			{ path, isDir, stats } = fileInfo

			if opts.isCacheStats
				statsCache[path] = stats

			list.push path
		.then ->
			list

	###*
	 * See `readDirsP`.
	 * @return {Array} Path string array.
	###
	readDirsSync: (root, opts = {}) ->
		_.defaults opts, {
			isCacheStats: false
			isIncludeRoot: false
		}

		list = []
		statsCache = {}
		Object.defineProperty list, 'statsCache', {
			value: statsCache
			enumerable: false
		}

		nofs.eachDirSync root, opts, (fileInfo) ->
			{ path, isDir, stats } = fileInfo

			if opts.isCacheStats
				statsCache[path] = stats

			list.push path

		list

	###*
	 * Read A Json file and parse it to a object.
	 * @param  {String} path
	 * @param  {Object | String} opts Same with the native `nofs.readFile`.
	 * @return {Promise} Resolves a parsed object.
	 * @example
	 * ```coffee
	 * nofs.readJsonP('a.json').then (obj) ->
	 * 	console.log obj.name, obj.age
	 * ```
	###
	readJsonP: (path, opts = {}) ->
		nofs.readFileP(path, opts).then (data) ->
			try
				JSON.parse data + ''
			catch err
				Promise.reject err

	###*
	 * See `readJSONP`.
	 * @return {Any} The parsed object.
	###
	readJsonSync: (path, opts = {}) ->
		data = nofs.readFileSync path, opts
		JSON.parse data + ''

	###*
	 * Walk through directory recursively with a callback.
	 * @param  {String}   path
	 * @param  {Object}   opts Extends the options of `eachDir`,
	 * with some extra options:
	 * ```coffee
	 * {
	 * 	# The init value of the walk.
	 * 	init: undefined
	 * }
	 * ```
	 * @param  {Function} fn `(prev, path, isDir, stats) -> Promise`
	 * @return {Promise} Final resolved value.
	 * @example
	 * ```coffee
	 * # Concat all files.
	 * nofs.reduceDirP 'dir/path', { init: '' }, (val, info) ->
	 * 	return val if info.isDir
	 * 	nofs.readFileP(info.path).then (str) ->
	 * 		val += str + '\n'
	 * .then (ret) ->
	 * 	console.log ret
	 * ```
	###
	reduceDirP: (path, opts = {}, fn) ->
		if _.isFunction opts
			fn = opts
			opts = {}

		prev = Promise.resolve opts.init

		nofs.eachDirP path, opts, (fileInfo) ->
			prev = prev.then (val) ->
				val = fn val, fileInfo
				if not val or not val.then
					Promise.resolve val
		.then ->
			prev

	###*
	 * See `reduceDirP`
	 * @return {Any} Final value.
	###
	reduceDirSync: (path, opts = {}, fn) ->
		if _.isFunction opts
			fn = opts
			opts = {}

		prev = opts.init

		nofs.eachDirSync path, opts, (fileInfo) ->
			prev = fn prev, fileInfo

		prev

	###*
	 * Remove a file or directory peacefully, same with the `rm -rf`.
	 * @param  {String} path
	 * @param {Object} opts Extends the options of `eachDir`. But
	 * the `isReverse` is fixed with `true`.
	 * @return {Promise}
	###
	removeP: (path, opts = {}) ->
		opts.isReverse = true

		nofs.statP(path).then (stats) ->
			if stats.isDirectory()
				nofs.eachDirP path, opts, ({ path, isDir }) ->
					if isDir
						nofs.rmdirP path
					else
						nofs.unlinkP path
			else
				nofs.unlinkP path
		.catch (err) ->
			if err.code != 'ENOENT' or err.path != path
				Promise.reject err

	###*
	 * See `removeP`.
	###
	removeSync: (path, opts = {}) ->
		opts.isReverse = true

		try
			stats = nofs.statSync(path)
			if stats.isDirectory()
				nofs.eachDirSync path, opts, ({ path, isDir }) ->
					if isDir
						nofs.rmdirSync path
					else
						nofs.unlinkSync path
			else
				nofs.unlinkSync path
		catch err
			if err.code != 'ENOENT' or err.path != path
				throw err

	###*
	 * Change file access and modification times.
	 * If the file does not exist, it is created.
	 * @param  {String} path
	 * @param  {Object} opts Default:
	 * ```coffee
	 * {
	 * 	atime: Date.now()
	 * 	mtime: Date.now()
	 * 	mode: undefined
	 * }
	 * ```
	 * @return {Promise} If new file created, resolves true.
	###
	touchP: (path, opts = {}) ->
		now = new Date
		_.defaults opts, {
			atime: now
			mtime: now
		}

		nofs.fileExistsP(path).then (exists) ->
			(if exists
				nofs.utimesP path, opts.atime, opts.mtime
			else
				nofs.outputFileP path, new Buffer(0), opts
			).then ->
				not exists

	###*
	 * See `touchP`.
	 * @return {Boolean} Whether a new file is created or not.
	###
	touchSync: (path, opts = {}) ->
		now = new Date
		_.defaults opts, {
			atime: now
			mtime: now
		}

		exists = nofs.fileExistsSync path
		if exists
			nofs.utimesSync path, opts.atime, opts.mtime
		else
			nofs.outputFileSync path, new Buffer(0), opts

		not exists

	###*
	 * Watch a file. If the file changes, the handler will be invoked.
	 * You can change the polling interval by using `process.env.pollingWatch`.
	 * Use `process.env.watchPersistent = 'off'` to disable the persistent.
	 * Why not use `nofs.watch`? Because `nofs.watch` is unstable on some file
	 * systems, such as Samba or OSX.
	 * @param  {String}   path    The file path
	 * @param  {Function} handler Event listener.
	 * The handler has these params:
	 * - file path
	 * - current `nofs.Stats`
	 * - previous `nofs.Stats`
	 * - if its a deletion
	 * @param {Boolean} autoUnwatch Auto unwatch the file while file deletion.
	 * Default is true.
	 * @return {Function} The wrapped watch listeners.
	 * @example
	 * ```coffee
	 * process.env.watchPersistent = 'off'
	 * nofs.watchFile 'a.js', (path, curr, prev, isDeletion) ->
	 * 	if curr.mtime != prev.mtime
	 * 		console.log path
	 * ```
	###
	watchFile: (path, handler, autoUnwatch = true) ->
		listener = (curr, prev) ->
			isDeletion = curr.mtime.getTime() == 0
			handler(path, curr, prev, isDeletion)
			if autoUnwatch and isDeletion
				nofs.unwatchFile path, listener

		fs.watchFile(
			path
			{
				persistent: process.env.watchPersistent != 'off'
				interval: +process.env.pollingWatch or 300
			}
			listener
		)
		listener

	###*
	 * Watch files, when file changes, the handler will be invoked.
	 * It is build on the top of `nofs.watchFile`.
	 * @param  {Array} patterns String array with minimatch syntax.
	 * Such as `['*\/**.css', 'lib\/**\/*.js']`.
	 * @param  {Function} handler
	 * @return {Promise} It contains the wrapped watch listeners.
	 * @example
	 * ```coffee
	 * nofs.watchFiles '*.js', (path, curr, prev, isDeletion) ->
	 * 	console.log path
	 * ```
	###
	watchFiles: (patterns, handler) ->
		nofs.globP(patterns).then (paths) ->
			paths.map (path) ->
				nofs.watchFile path, handler

	###*
	 * Watch directory and all the files in it.
	 * It supports three types of change: create, modify, move, delete.
	 * By default, `move` event is disabled.
	 * It is build on the top of `nofs.watchFile`.
	 * @param  {Object} opts Defaults:
	 * ```coffee
	 * {
	 * 	dir: '.'
	 * 	pattern: '**' # minimatch, string or array
	 *
	 * 	# Whether to watch POSIX hidden file.
	 * 	dot: false
	 *
	 * 	# If the "path" ends with '/' it's a directory, else a file.
	 * 	handler: (type, path, oldPath) ->
	 *
	 * 	# The minimatch options.
	 * 	minimatch: {}
	 *
	 * 	isEnableMoveEvent: false
	 * }
	 * ```
	 * @return {Promise}
	 * @example
	 * ```coffee
	 * # Only current folder, and only watch js and css file.
	 * nofs.watchDir {
	 * 	dir: 'lib'
	 * 	pattern: '*.+(js|css)'
	 * 	handler: (type, path) ->
	 * 		console.log type
	 * 		console.log path
	 * }
	 * ```
	###
	watchDir: (opts = {}) ->
		_.defaults opts, {
			dir: '.'
			pattern: '**'
			minimatch: {}
			all: false
			handler: (type, path, oldPath) ->
			error: (err) ->
				console.error err
		}

		opts.minimatch.dot = opts.all

		watchedList = {}

		isSameFile = (statsA, statsB) ->
			# On Unix just "ino" will do the trick, but on Windows
			# "ino" is always zero.
			if statsA.ctime.ino != 0 and statsA.ctime.ino == statsB.ctime.ino
				return true

			# Since "size" for Windows is always zero, and the unit of "time"
			# is second, the code below is not reliable.
			statsA.mtime.getTime() == statsB.mtime.getTime() and
			statsA.ctime.getTime() == statsB.ctime.getTime() and
			statsA.size == statsB.size

		match = (path, pattern) ->
			nofs.minimatch path, pattern, opts.minimatch

		dirPath = (dir) -> npath.join dir, '/'

		fileHandler = (path, curr, prev, isDelete) ->
			if isDelete
				opts.handler 'delete', path
			else
				opts.handler 'modify', path

		dirHandler = (dir, curr, prev, isDelete) ->
			# Possible Event Order
			# 1. modify event: file modify.
			# 2. delete event: file delete -> parent modify.
			# 3. create event: parent modify -> file create.
			# 4.   move event: file delete -> parent modify -> file create.

			if isDelete
				opts.handler 'delete', dirPath(dir)
				return

			pattern = npath.join dir, opts.pattern

			# Prevent high frequency concurrent fs changes,
			# we should to use Sync function here. But for
			# now if we don't need `move` event, everything is OK.
			nofs.eachDirP dir, {
				all: opts.all
			}, (fileInfo) ->
				path = fileInfo.path
				if watchedList[path]
					return

				watchedList[path] =
				if fileInfo.isDir
					opts.handler 'create', dirPath(path) if curr
					nofs.watchFile path, dirHandler
				else
					if match path, pattern
						opts.handler 'create', path if curr
						nofs.watchFile path, fileHandler

		dirHandler opts.dir

	###*
	 * A `writeFile` shim for `< Node v0.10`.
	 * @param  {String} path
	 * @param  {String | Buffer} data
	 * @param  {String | Object} opts
	 * @return {Promise}
	###
	writeFileP: (path, data, opts = {}) ->
		switch typeof opts
			when 'string'
				encoding = opts
			when 'object'
				{ encoding, flag, mode } = opts
			else
				throw new TypeError('Bad arguments')

		flag ?= 'w'
		mode ?= 0o666

		nofs.openP(path, flag, mode).then (fd) ->
			buf = if data.constructor.name == 'Buffer'
				data
			else
				new Buffer('' + data, encoding)
			pos = if flag.indexOf('a') > -1 then null else 0
			nofs.writeP fd, buf, 0, buf.length, pos

	###*
	 * See `writeFileP`
	###
	writeFileSync: (path, data, opts = {}) ->
		switch typeof opts
			when 'string'
				encoding = opts
			when 'object'
				{ encoding, flag, mode } = opts
			else
				throw new TypeError('Bad arguments')

		flag ?= 'w'
		mode ?= 0o666

		fd = nofs.openSync(path, flag, mode)
		buf = if data.constructor.name == 'Buffer'
			data
		else
			new Buffer('' + data, encoding)
		pos = if flag.indexOf('a') > -1 then null else 0
		nofs.writeSync fd, buf, 0, buf.length, pos

}

for k of nofs
	if k.slice(-1) == 'P'
		name = k[0...-1]
		continue if nofs[name]
		nofs[name] = _.callbackify nofs[k]

require('./alias')(nofs)

module.exports = nofs
