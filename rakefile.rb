# =============================================================================
#
# MODULE      : rakefile.rb
# PROJECT     : crossgo
# DESCRIPTION :
#
# Copyright (c) 2016-2020, Marc-Antoine Argenton.  All rights reserved.
# =============================================================================

require 'fileutils'

task default: [:run]

desc 'Display version and information that will be incldued in build'
task :info do
    puts "Version: #{BuildInfo.default.version}"
end

desc 'Build and publish both release archive and associated container image'
task :build do
    FileUtils.makedirs( ['./build/artifacts', './build/bin'] )
    FileUtils.cp( "./content/crossgo", "./build/bin" )
    FileUtils.chmod( 'a+x', "./build/bin/crossgo" )

    # Inject build version into crossgo script
    version = BuildInfo.default.version
    sed_script = "s/^CROSSGO_VERSION=.*/CROSSGO_VERSION=#{version}/"
    cmd = %w(sed -r -i) + [sed_script] + %w(build/bin/crossgo)
    system(*cmd)
    fail( "Failed to patch crossgo script with version string" ) if $?.exitstatus != 0

    # Build release archive
    archive_name = "./artifacts/crossgo-#{version}.tar.gz"
    system( "cd build; tar czf #{archive_name} bin" )
    system( "cd build/artifacts; shasum -a 256 *.tar.gz > checksumfile" )

    # Generate release notes
    rn = generate_release_notes("crossgo", version,
        input:'doc/RELEASES.md',
        checksums:'build/artifacts/checksumfile'
    )
    File.write( 'build/release_notes', rn)

    # Build container image
    system( "docker build -t maargenton/crossgo:#{version} ." )
    fail( "Failed to build docker image" ) if $?.exitstatus != 0
end

desc 'Publish crossgo image and release archive after building it'
task :publish => [:build] do
    username = ENV['DOCKER_USERNAME'] || ""
    push_key = ENV['DOCKER_PUSH_KEY'] || ""
    if !username.empty? && !push_key.empty?
        puts "Authenticating with docker.com for user #{username}..."
        system("echo #{push_key} | docker login --username #{username} --password-stdin")
        puts "Failed to authenticate with docker.com" if $?.exitstatus != 0
    end

    version = BuildInfo.default.version
    image_name = "maargenton/crossgo:#{version}"
    system( "docker push #{image_name}")
    fail( "Failed to push docker image" ) if $?.exitstatus != 0
end

desc 'Build crossgo image and run it interactively'
task :run => [:build] do
    system( "cd build; ./bin/crossgo" )
end


desc 'Remove build artifacts'
task :clean do
    FileUtils.rm_rf('./build')
end



# ----------------------------------------------------------------------------
# BuildInfo : Helper to extract version inforrmation for git repo
# ----------------------------------------------------------------------------

class BuildInfo
    class << self
        def default() return @default ||= new end
    end

    def initialize()
        if _git('rev-parse --is-shallow-repository') == 'true'
            puts "Fetching missing information from remote ..."
            system(' git fetch --prune --tags --unshallow')
        end
    end

    def version()   return @version ||= _version()  end
    def remote()    return @remote  ||= _remote()   end
    def commit()    return @commit  ||= _commit()   end
    def dir()       return @dir     ||= _dir()      end

    private
    def _git( cmd ) return `git #{cmd} 2>/dev/null`.strip()     end
    def _commit()   return _git('rev-parse HEAD')               end
    def _dir()      return _git('rev-parse --show-toplevel')    end

    def _version()
        v, b, n, g = _info()
        m = _mtag()
        return v if (b == 'master' || b == 'HEAD' || v.start_with?(b)) && n == 0 && m.nil?
        return "#{v}-" + [b, n, g, m].compact().join('.')
    end

    def _info()
        # Note: Due to glob(7) limitations, the following pattern enforces
        # 3-part dot-separated sequences starting with a digit,
        # rather than 3 dot-separated numbers.
        d = _git("describe --always --tags --long  --match 'v[0-9]*.[0-9]*.[0-9]*'").strip.split('-')
        if d.count != 0
            b = _git("rev-parse --abbrev-ref HEAD").strip.gsub(/[^A-Za-z0-9\._-]+/, '-')
            return ['v0.0.0', b, _git("rev-list --count HEAD").strip.to_i, "g#{d[0]}"] if d.count == 1
            return [d[0], b, d[1].to_i, d[2]] if d.count == 3
        end
        return ['v0.0.0', "none", 0, 'g0000000']
    end

    def _mtag()
        status = _git("status --porcelain=2 --untracked-files=no")
        files = status.lines.map {|l| l.strip.split(/ +/).last }.map { |n| n.split(/\t/).first }
        t = files.map { |f| File.mtime(f).to_i rescue nil }.compact.max
        return t.nil? ? nil : "m%08x" % t
    end

    GIT_SSH_REPO = /git@(?<host>[^:]+):(?<path>.+).git/
    def _remote()
        remote = _git('remote get-url origin')
        m = GIT_SSH_REPO.match(remote)
        return remote if m.nil?

        host = m[:host]
        host = "github.com" if host.end_with? ("github.com")
        return "https://#{host}/#{m[:path]}/"
    end
end



# ----------------------------------------------------------------------------
# Release notes generator
# ----------------------------------------------------------------------------

def generate_release_notes(prefix, version, input:nil, checksums:nil)
    rn = "#{prefix} #{version}\n\n"
    rn += load_release_notes(input, version) if input
    rn += "\n## Checksums\n\n```\n" + File.read(checksums) + "```\n" if checksums
    rn
end

def load_release_notes(filename, version)
    notes, capture = [], false
    File.readlines(filename).each do |l|
        if l.start_with?( "# ")
            break if capture
            capture = true if l[2..-1].strip() == version
        elsif capture
            notes << l
        end
    end
    notes.shift while (notes.first || "-").strip == ""
    return notes.join()
end



# ----------------------------------------------------------------------------
# Definitions to help formating 'rake watch' results
# ----------------------------------------------------------------------------

TERM_WIDTH = `tput cols`.to_i || 80

def tty_red(str);           "\e[31m#{str}\e[0m" end
def tty_green(str);         "\e[32m#{str}\e[0m" end
def tty_blink(str);         "\e[5m#{str}\e[25m" end
def tty_reverse_color(str); "\e[7m#{str}\e[27m" end

def print_separator( success = true )
    if success
        puts tty_green( "-" * TERM_WIDTH )
    else
        puts tty_reverse_color(tty_red( "-" * TERM_WIDTH ))
    end
end



# ----------------------------------------------------------------------------
# Definition of watch task, that monitors the project folder for any relevant
# file change and runs the unit test of the project.
# ----------------------------------------------------------------------------

def watch( *glob )
    yield unless block_given?
    files = []
    loop do
        new_files = Dir[*glob].map {|file| File.mtime(file) }
        yield if new_files != files
        files = new_files
        sleep 0.5
    end
end

task :watch do
    watch( '**/*.{c,cc,cpp,h,hh,hpp,ld}', 'Makefile' ) do
        success = system "clear && rake"
        print_separator( success )
    end
end
