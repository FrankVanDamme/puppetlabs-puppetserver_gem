require 'puppet/provider/package'
require 'uri'

# Ruby gems support.
Puppet::Type.type(:package).provide :puppetserver_gem, :parent => :gem do
  desc "Puppet Server Ruby Gem support. If a URL is passed via `source`, then
    that URL is appended to the list of remote gem repositories which by default
    contains rubygems.org; To ensure that only the specified source is used also
    pass `--clear-sources` in via `install_options`; if a source is present but is
    not a valid URL, it will be interpreted as the path to a local gem file.  If
    source is not present at all, the gem will be installed from the default gem
    repositories."

  has_feature :versionable, :install_options, :uninstall_options

  commands :puppetservercmd => "/opt/puppetlabs/bin/puppetserver"

  # the HOME variable is lost to the puppetserver script and needs to be
  # injected directly into the call to `execute()`
  CMD_ENV = {:custom_environment => {:HOME => ENV['HOME']}}


  def self.gemlist(options)
    gem_list_command = [command(:puppetservercmd), "gem", "list"]

    if options[:local]
      gem_list_command << "--local"
    else
      gem_list_command << "--remote"
    end
    if options[:source]
      gem_list_command << "--source" << options[:source]
    end
    if name = options[:justme]
      gem_list_command << "^" + name + "$"
    end

    begin
      list = execute(gem_list_command, CMD_ENV).lines.
          map {|set| gemsplit(set) }.
          reject {|x| x.nil? }
    rescue Puppet::ExecutionFailure => detail
      raise Puppet::Error, "Could not list gems: #{detail}", detail.backtrace
    end

    if options[:justme]
      return list.shift
    else
      return list
    end
  end

  def install(useversion = true)
    command = [command(:puppetservercmd), "gem", "install"]
    command += install_options if resource[:install_options]
    command << "-v" << resource[:ensure] if (! resource[:ensure].is_a? Symbol) and useversion

    if source = resource[:source]
      begin
        uri = URI.parse(source)
      rescue => detail
        self.fail Puppet::Error, "Invalid source '#{uri}': #{detail}", detail
      end

      case uri.scheme
        when nil
          # no URI scheme => interpret the source as a local file
          command << source
        when /file/i
          command << uri.path
        when 'puppet'
          # we don't support puppet:// URLs (yet)
          raise Puppet::Error.new("puppet:// URLs are not supported as gem sources")
        else
          # interpret it as a gem repository
          command << "--source" << "#{source}" << resource[:name]
      end
    else
      command << resource[:name]
    end

    output = execute(command, CMD_ENV)
    # Apparently some stupid gem versions don't exit non-0 on failure
    self.fail "Could not install: #{output.chomp}" if output.include?("ERROR")
  end

  def uninstall
    command = [command(:puppetservercmd), "gem", "uninstall"]
    command << "-x" << "-a" << resource[:name]

    output = execute(command, CMD_ENV)
    self.fail "Could not uninstall: #{output.chomp}" if output.include?("ERROR")
  end
end
