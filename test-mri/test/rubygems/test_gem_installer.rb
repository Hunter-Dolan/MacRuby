require 'rubygems/installer_test_case'

class TestGemInstaller < Gem::InstallerTestCase

  def setup
    super

    if __name__ !~ /^test_install(_|$)/ then
      @gemhome = @installer_tmp
      Gem.use_paths @installer_tmp

      @spec = Gem::Specification.find_by_name 'a'
      @user_spec = Gem::Specification.find_by_name 'b'

      @installer.spec = @spec
      @installer.gem_home = @installer_tmp
      @installer.gem_dir = @spec.gem_dir
      @user_installer.spec = @user_spec
      @user_installer.gem_home = @installer_tmp
    end
  end


  def test_app_script_text
    @spec.version = 2
    util_make_exec @spec, ''

    expected = <<-EOF
#!#{Gem.ruby}
#
# This file was generated by RubyGems.
#
# The application 'a' is installed as part of a gem, and
# this file is here to facilitate running it.
#

require 'rubygems'

version = \">= 0\"

if ARGV.first =~ /^_(.*)_$/ and Gem::Version.correct? $1 then
  version = $1
  ARGV.shift
end

gem 'a', version
load Gem.bin_path('a', 'executable', version)
    EOF

    wrapper = @installer.app_script_text 'executable'
    assert_equal expected, wrapper
  end

  def test_build_extensions_none
    use_ui @ui do
      @installer.build_extensions
    end

    assert_equal '', @ui.output
    assert_equal '', @ui.error

    refute File.exist?('gem_make.out')
  end

  def test_build_extensions_extconf_bad
    @spec.extensions << 'extconf.rb'

    e = assert_raises Gem::Installer::ExtensionBuildError do
      use_ui @ui do
        @installer.build_extensions
      end
    end

    assert_match(/\AERROR: Failed to build gem native extension.$/, e.message)

    assert_equal "Building native extensions.  This could take a while...\n",
                 @ui.output
    assert_equal '', @ui.error

    gem_make_out = File.join @gemhome, 'gems', @spec.full_name, 'gem_make.out'

    assert_match %r%#{Regexp.escape Gem.ruby} extconf\.rb%,
                 File.read(gem_make_out)
    assert_match %r%#{Regexp.escape Gem.ruby}: No such file%,
                 File.read(gem_make_out)
  end

  def test_build_extensions_unsupported
    gem_make_out = File.join @gemhome, 'gems', @spec.full_name, 'gem_make.out'
    @spec.extensions << nil

    e = assert_raises Gem::Installer::ExtensionBuildError do
      use_ui @ui do
        @installer.build_extensions
      end
    end

    assert_match(/^\s*No builder for extension ''$/, e.message)

    assert_equal "Building native extensions.  This could take a while...\n",
                 @ui.output
    assert_equal '', @ui.error

    assert_equal "No builder for extension ''\n", File.read(gem_make_out)
  ensure
    FileUtils.rm_f gem_make_out
  end

  def test_ensure_dependency
    dep = Gem::Dependency.new 'a', '>= 2'
    assert @installer.ensure_dependency(@spec, dep)

    dep = Gem::Dependency.new 'b', '> 2'
    e = assert_raises Gem::InstallError do
      @installer.ensure_dependency @spec, dep
    end

    assert_equal 'a requires b (> 2)', e.message
  end

  def test_extract_files
    format = Object.new
    def format.file_entries
      [[{'size' => 7, 'mode' => 0400, 'path' => 'thefile'}, 'content']]
    end

    @installer.format = format

    @installer.extract_files

    thefile_path = File.join(util_gem_dir, 'thefile')
    assert_equal 'content', File.read(thefile_path)

    unless Gem.win_platform? then
      assert_equal 0400, File.stat(thefile_path).mode & 0777
    end
  end

  def test_extract_files_bad_dest
    @installer.gem_dir = 'somedir'
    @installer.format = nil
    e = assert_raises ArgumentError do
      @installer.extract_files
    end

    assert_equal 'format required to extract from', e.message
  end

  def test_extract_files_relative
    format = Object.new
    def format.file_entries
      [[{'size' => 10, 'mode' => 0644, 'path' => '../thefile'}, '../thefile']]
    end

    @installer.format = format

    e = assert_raises Gem::InstallError do
      @installer.extract_files
    end

    dir = util_gem_dir
    expected = "attempt to install file into \"../thefile\" under #{dir}"
    assert_equal expected, e.message
    assert_equal false, File.file?(File.join(@tempdir, '../thefile')),
                 "You may need to remove this file if you broke the test once"
  end

  def test_extract_files_absolute
    format = Object.new
    def format.file_entries
      [[{'size' => 8, 'mode' => 0644, 'path' => '/thefile'}, '/thefile']]
    end

    @installer.format = format

    e = assert_raises Gem::InstallError do
      @installer.extract_files
    end

    assert_equal 'attempt to install file into /thefile', e.message
    assert_equal false, File.file?(File.join('/thefile')),
                 "You may need to remove this file if you broke the test once"
  end

  def test_generate_bin_bindir
    @installer.wrappers = true

    @spec.executables = %w[executable]
    @spec.bindir = '.'

    exec_file = @installer.formatted_program_filename 'executable'
    exec_path = File.join util_gem_dir(@spec), exec_file
    File.open exec_path, 'w' do |f|
      f.puts '#!/usr/bin/ruby'
    end

    @installer.gem_dir = util_gem_dir

    @installer.generate_bin

    assert_equal true, File.directory?(util_inst_bindir)
    installed_exec = File.join(util_inst_bindir, 'executable')
    assert_equal true, File.exist?(installed_exec)
    assert_equal mask, File.stat(installed_exec).mode unless win_platform?

    wrapper = File.read installed_exec
    assert_match %r|generated by RubyGems|, wrapper
  end

  def test_generate_bin_bindir_with_user_install_warning
    bin_dir = Gem.win_platform? ? File.expand_path(ENV["WINDIR"]) : "/usr/bin"

    options = {
      :bin_dir => bin_dir,
      :install_dir => "/non/existant"
    }

    inst = Gem::Installer.new nil, options

    Gem::Installer.path_warning = false

    use_ui @ui do
      inst.check_that_user_bin_dir_is_in_path
    end

    assert_equal "", @ui.error
  end

  def test_generate_bin_script
    @installer.wrappers = true
    util_make_exec
    @installer.gem_dir = util_gem_dir

    @installer.generate_bin
    assert_equal true, File.directory?(util_inst_bindir)
    installed_exec = File.join(util_inst_bindir, 'executable')
    assert_equal true, File.exist?(installed_exec)
    assert_equal mask, File.stat(installed_exec).mode unless win_platform?

    wrapper = File.read installed_exec
    assert_match %r|generated by RubyGems|, wrapper
  end

  def test_generate_bin_script_format
    @installer.format_executable = true
    @installer.wrappers = true
    util_make_exec
    @installer.gem_dir = util_gem_dir

    Gem::Installer.exec_format = 'foo-%s-bar'
    @installer.generate_bin
    assert_equal true, File.directory?(util_inst_bindir)
    installed_exec = File.join util_inst_bindir, 'foo-executable-bar'
    assert_equal true, File.exist?(installed_exec)
  ensure
    Gem::Installer.exec_format = nil
  end

  def test_generate_bin_script_format_disabled
    @installer.wrappers = true
    util_make_exec
    @installer.gem_dir = util_gem_dir

    Gem::Installer.exec_format = 'foo-%s-bar'
    @installer.generate_bin
    assert_equal true, File.directory?(util_inst_bindir)
    installed_exec = File.join util_inst_bindir, 'executable'
    assert_equal true, File.exist?(installed_exec)
  ensure
    Gem::Installer.exec_format = nil
  end

  def test_generate_bin_script_install_dir
    @installer.wrappers = true
    @spec.executables = %w[executable]

    gem_dir = File.join("#{@gemhome}2", "gems", @spec.full_name)
    gem_bindir = File.join gem_dir, 'bin'
    FileUtils.mkdir_p gem_bindir
    File.open File.join(gem_bindir, 'executable'), 'w' do |f|
      f.puts "#!/bin/ruby"
    end

    @installer.gem_home = "#{@gemhome}2"
    @installer.gem_dir = gem_dir

    @installer.generate_bin

    installed_exec = File.join("#{@gemhome}2", "bin", 'executable')
    assert_equal true, File.exist?(installed_exec)
    assert_equal mask, File.stat(installed_exec).mode unless win_platform?

    wrapper = File.read installed_exec
    assert_match %r|generated by RubyGems|, wrapper
  end

  def test_generate_bin_script_no_execs
    util_execless

    @installer.wrappers = true
    @installer.generate_bin

    refute File.exist?(util_inst_bindir), 'bin dir was created when not needed'
  end

  def test_generate_bin_script_no_perms
    @installer.wrappers = true
    util_make_exec

    Dir.mkdir util_inst_bindir

    if win_platform?
      skip('test_generate_bin_script_no_perms skipped on MS Windows')
    else
      FileUtils.chmod 0000, util_inst_bindir

      assert_raises Gem::FilePermissionError do
        @installer.generate_bin
      end
    end
  ensure
    FileUtils.chmod 0755, util_inst_bindir unless ($DEBUG or win_platform?)
  end

  def test_generate_bin_script_no_shebang
    @installer.wrappers = true
    @spec.executables = %w[executable]

    gem_dir = File.join @gemhome, 'gems', @spec.full_name
    gem_bindir = File.join gem_dir, 'bin'
    FileUtils.mkdir_p gem_bindir
    File.open File.join(gem_bindir, 'executable'), 'w' do |f|
      f.puts "blah blah blah"
    end

    @installer.generate_bin

    installed_exec = File.join @gemhome, 'bin', 'executable'
    assert_equal true, File.exist?(installed_exec)
    assert_equal mask, File.stat(installed_exec).mode unless win_platform?

    wrapper = File.read installed_exec
    assert_match %r|generated by RubyGems|, wrapper
    # HACK some gems don't have #! in their executables, restore 2008/06
    #assert_no_match %r|generated by RubyGems|, wrapper
  end

  def test_generate_bin_script_wrappers
    skip("[BUG : #???] Timeout, MacRuby don't finish")

    @installer.wrappers = true
    util_make_exec
    @installer.gem_dir = util_gem_dir
    installed_exec = File.join(util_inst_bindir, 'executable')

    real_exec = File.join util_gem_dir, 'bin', 'executable'

    # fake --no-wrappers for previous install
    unless Gem.win_platform? then
      FileUtils.mkdir_p File.dirname(installed_exec)
      FileUtils.ln_s real_exec, installed_exec
    end

    @installer.generate_bin
    assert_equal true, File.directory?(util_inst_bindir)
    assert_equal true, File.exist?(installed_exec)
    assert_equal mask, File.stat(installed_exec).mode unless win_platform?

    assert_match %r|generated by RubyGems|, File.read(installed_exec)

    refute_match %r|generated by RubyGems|, File.read(real_exec),
                 'real executable overwritten'
  end

  def test_generate_bin_symlink
    return if win_platform? #Windows FS do not support symlinks

    @installer.wrappers = false
    util_make_exec
    @installer.gem_dir = util_gem_dir

    @installer.generate_bin
    assert_equal true, File.directory?(util_inst_bindir)
    installed_exec = File.join util_inst_bindir, 'executable'
    assert_equal true, File.symlink?(installed_exec)
    assert_equal(File.join(util_gem_dir, 'bin', 'executable'),
                 File.readlink(installed_exec))
  end

  def test_generate_bin_symlink_no_execs
    util_execless

    @installer.wrappers = false
    @installer.generate_bin

    refute File.exist?(util_inst_bindir)
  end

  def test_generate_bin_symlink_no_perms
    @installer.wrappers = false
    util_make_exec
    @installer.gem_dir = util_gem_dir

    Dir.mkdir util_inst_bindir

    if win_platform?
      skip('test_generate_bin_symlink_no_perms skipped on MS Windows')
    else
      FileUtils.chmod 0000, util_inst_bindir

      assert_raises Gem::FilePermissionError do
        @installer.generate_bin
      end
    end
  ensure
    FileUtils.chmod 0755, util_inst_bindir unless ($DEBUG or win_platform?)
  end

  def test_generate_bin_symlink_update_newer
    return if win_platform? #Windows FS do not support symlinks

    @installer.wrappers = false
    util_make_exec
    @installer.gem_dir = util_gem_dir

    @installer.generate_bin
    installed_exec = File.join(util_inst_bindir, 'executable')
    assert_equal(File.join(util_gem_dir, 'bin', 'executable'),
                 File.readlink(installed_exec))

    @spec = Gem::Specification.new do |s|
      s.files = ['lib/code.rb']
      s.name = "a"
      s.version = "3"
      s.summary = "summary"
      s.description = "desc"
      s.require_path = 'lib'
    end

    @spec.version = 3
    util_make_exec
    @installer.gem_dir = util_gem_dir @spec
    @installer.generate_bin
    installed_exec = File.join(util_inst_bindir, 'executable')
    assert_equal(@spec.bin_file('executable'),
                 File.readlink(installed_exec),
                 "Ensure symlink moved to latest version")
  end

  def test_generate_bin_symlink_update_older
    return if win_platform? #Windows FS do not support symlinks

    @installer.wrappers = false
    util_make_exec
    @installer.gem_dir = util_gem_dir

    @installer.generate_bin
    installed_exec = File.join(util_inst_bindir, 'executable')
    assert_equal(File.join(util_gem_dir, 'bin', 'executable'),
                 File.readlink(installed_exec))

    spec = Gem::Specification.new do |s|
      s.files = ['lib/code.rb']
      s.name = "a"
      s.version = "1"
      s.summary = "summary"
      s.description = "desc"
      s.require_path = 'lib'
    end

    util_make_exec
    one = @spec.dup
    one.version = 1
    @installer.gem_dir = util_gem_dir one
    @installer.spec = spec

    @installer.generate_bin

    installed_exec = File.join util_inst_bindir, 'executable'
    expected = File.join util_gem_dir, 'bin', 'executable'
    assert_equal(expected,
                 File.readlink(installed_exec),
                 "Ensure symlink not moved")
  end

  def test_generate_bin_symlink_update_remove_wrapper
    return if win_platform? #Windows FS do not support symlinks

    @installer.wrappers = true
    util_make_exec
    @installer.gem_dir = util_gem_dir

    @installer.generate_bin
    installed_exec = File.join util_inst_bindir, 'executable'
    assert_equal true, File.exist?(installed_exec)

    @spec = Gem::Specification.new do |s|
      s.files = ['lib/code.rb']
      s.name = "a"
      s.version = "3"
      s.summary = "summary"
      s.description = "desc"
      s.require_path = 'lib'
    end

    @installer.wrappers = false
    @spec.version = 3
    util_make_exec
    @installer.gem_dir = util_gem_dir
    @installer.generate_bin
    installed_exec = File.join(util_inst_bindir, 'executable')
    assert_equal(File.join(util_gem_dir, 'bin', 'executable'),
                 File.readlink(installed_exec),
                 "Ensure symlink moved to latest version")
  end

  def test_generate_bin_symlink_win32
    old_win_platform = Gem.win_platform?
    Gem.win_platform = true
    @installer.wrappers = false
    util_make_exec
    @installer.gem_dir = util_gem_dir

    use_ui @ui do
      @installer.generate_bin
    end

    assert_equal true, File.directory?(util_inst_bindir)
    installed_exec = File.join(util_inst_bindir, 'executable')
    assert_equal true, File.exist?(installed_exec)

    assert_match(/Unable to use symlinks on Windows, installing wrapper/i,
                 @ui.error)

    wrapper = File.read installed_exec
    assert_match(/generated by RubyGems/, wrapper)
  ensure
    Gem.win_platform = old_win_platform
  end

  def test_generate_bin_uses_default_shebang
    return if win_platform? #Windows FS do not support symlinks

    @installer.wrappers = true
    util_make_exec

    @installer.generate_bin

    default_shebang = Gem.ruby
    shebang_line = open("#{@gemhome}/bin/executable") { |f| f.readlines.first }
    assert_match(/\A#!/, shebang_line)
    assert_match(/#{default_shebang}/, shebang_line)
  end

  def test_initialize
    spec = quick_spec 'a' do |s| s.platform = Gem::Platform.new 'mswin32' end
    gem = File.join @tempdir, spec.file_name

    Dir.mkdir util_inst_bindir
    util_build_gem spec
    FileUtils.mv spec.cache_file, @tempdir

    installer = Gem::Installer.new gem

    assert_equal File.join(@gemhome, 'gems', spec.full_name), installer.gem_dir
  end

  def test_install
    Dir.mkdir util_inst_bindir
    util_setup_gem
    util_clear_gems

    gemdir     = File.join @gemhome, 'gems', @spec.full_name
    cache_file = File.join @gemhome, 'cache', @spec.file_name
    stub_exe   = File.join @gemhome, 'bin', 'executable'
    rakefile   = File.join gemdir, 'ext', 'a', 'Rakefile'

    Gem.pre_install do |installer|
      refute File.exist?(cache_file), 'cache file must not exist yet'
      true
    end

    Gem.post_build do |installer|
      assert File.exist?(gemdir), 'gem install dir must exist'
      assert File.exist?(rakefile), 'gem executable must exist'
      refute File.exist?(stub_exe), 'gem executable must not exist'
      true
    end

    Gem.post_install do |installer|
      assert File.exist?(cache_file), 'cache file must exist'
    end

    @newspec = nil
    build_rake_in do
      use_ui @ui do
        @newspec = @installer.install
      end
    end

    assert_equal @spec, @newspec
    assert File.exist? gemdir
    assert File.exist?(stub_exe), 'gem executable must exist'

    exe = File.join gemdir, 'bin', 'executable'
    assert File.exist? exe

    exe_mode = File.stat(exe).mode & 0111
    assert_equal 0111, exe_mode, "0%o" % exe_mode unless win_platform?

    assert File.exist?(File.join(gemdir, 'lib', 'code.rb'))

    assert File.exist? rakefile

    spec_file = File.join(@gemhome, 'specifications', @spec.spec_name)

    assert_equal spec_file, @newspec.loaded_from
    assert File.exist?(spec_file)

    assert_same @installer, @post_build_hook_arg
    assert_same @installer, @post_install_hook_arg
    assert_same @installer, @pre_install_hook_arg
  end

  def test_install_with_no_prior_files
    Dir.mkdir util_inst_bindir
    util_clear_gems

    util_setup_gem
    build_rake_in do
      use_ui @ui do
        assert_equal @spec, @installer.install
      end
    end

    gemdir = File.join(@gemhome, 'gems', @spec.full_name)
    assert File.exist?(File.join(gemdir, 'lib', 'code.rb'))

    util_setup_gem
    # Morph spec to have lib/other.rb instead of code.rb and recreate
    @spec.files = File.join('lib', 'other.rb')
    Dir.chdir @tempdir do
      File.open File.join('lib', 'other.rb'), 'w' do |f| f.puts '1' end
      use_ui ui do
        FileUtils.rm @gem
        Gem::Builder.new(@spec).build
      end
    end
    @installer = Gem::Installer.new @gem
    build_rake_in do
      use_ui @ui do
        assert_equal @spec, @installer.install
      end
    end

    assert File.exist?(File.join(gemdir, 'lib', 'other.rb'))
    refute(File.exist?(File.join(gemdir, 'lib', 'code.rb')),
           "code.rb from prior install of same gem shouldn't remain here")
  end

  def test_install_bad_gem
    gem = nil

    use_ui @ui do
      Dir.chdir @tempdir do Gem::Builder.new(@spec).build end
      gem = File.join @tempdir, @spec.file_name
    end

    gem_data = File.open gem, 'rb' do |fp| fp.read 1024 end
    File.open gem, 'wb' do |fp| fp.write gem_data end

    e = assert_raises Gem::InstallError do
      use_ui @ui do
        @installer = Gem::Installer.new gem
        @installer.install
      end
    end

    assert_equal "invalid gem format for #{gem}", e.message
  end

  def test_install_check_dependencies
    @spec.add_dependency 'b', '> 5'
    util_setup_gem

    use_ui @ui do
      assert_raises Gem::InstallError do
        @installer.install
      end
    end
  end

  def test_install_check_dependencies_install_dir
    gemhome2 = "#{@gemhome}2"
    @spec.add_dependency 'b'

    quick_gem 'b', 2

    FileUtils.mv @gemhome, gemhome2

    Gem::Specification.dirs = [gemhome2] # TODO: switch all dirs= to use_paths

    util_setup_gem

    @installer = Gem::Installer.new @gem, :install_dir => gemhome2

    gem_home = Gem.dir

    build_rake_in do
      use_ui @ui do
        @installer.install
      end
    end

    assert File.exist?(File.join(gemhome2, 'gems', @spec.full_name))
    assert_equal gem_home, Gem.dir
  end

  def test_install_force
    use_ui @ui do
      installer = Gem::Installer.new old_ruby_required, :force => true
      installer.install
    end

    gem_dir = File.join(@gemhome, 'gems', 'old_ruby_required-1')
    assert File.exist?(gem_dir)
  end

  def test_install_ignore_dependencies
    Dir.mkdir util_inst_bindir
    @spec.add_dependency 'b', '> 5'
    util_setup_gem
    @installer.ignore_dependencies = true

    build_rake_in do
      use_ui @ui do
        assert_equal @spec, @installer.install
      end
    end

    gemdir = File.join @gemhome, 'gems', @spec.full_name
    assert File.exist?(gemdir)

    exe = File.join(gemdir, 'bin', 'executable')
    assert File.exist?(exe)
    exe_mode = File.stat(exe).mode & 0111
    assert_equal 0111, exe_mode, "0%o" % exe_mode unless win_platform?
    assert File.exist?(File.join(gemdir, 'lib', 'code.rb'))

    assert File.exist?(File.join(@gemhome, 'specifications', @spec.spec_name))
  end

  def test_install_missing_dirs
    FileUtils.rm_f File.join(Gem.dir, 'cache')
    FileUtils.rm_f File.join(Gem.dir, 'docs')
    FileUtils.rm_f File.join(Gem.dir, 'specifications')

    use_ui @ui do
      Dir.chdir @tempdir do Gem::Builder.new(@spec).build end

      @installer.install
    end

    File.directory? File.join(Gem.dir, 'cache')
    File.directory? File.join(Gem.dir, 'docs')
    File.directory? File.join(Gem.dir, 'specifications')

    assert File.exist?(File.join(@gemhome, 'cache', @spec.file_name))
    assert File.exist?(File.join(@gemhome, 'specifications', @spec.spec_name))
  end

  def test_install_post_build_false
    util_clear_gems

    Gem.post_build do
      false
    end

    use_ui @ui do
      e = assert_raises Gem::InstallError do
        @installer.install
      end

      location = "#{__FILE__}:#{__LINE__ - 9}"

      assert_equal "post-build hook at #{location} failed for a-2", e.message
    end

    spec_file = File.join @gemhome, 'specifications', @spec.spec_name
    refute File.exist? spec_file

    gem_dir = File.join @gemhome, 'gems', @spec.full_name
    refute File.exist? gem_dir
  end

  def test_install_post_build_nil
    util_clear_gems

    Gem.post_build do
      nil
    end

    use_ui @ui do
      @installer.install
    end

    spec_file = File.join @gemhome, 'specifications', @spec.spec_name
    assert File.exist? spec_file

    gem_dir = File.join @gemhome, 'gems', @spec.full_name
    assert File.exist? gem_dir
  end

  def test_install_pre_install_false
    util_clear_gems

    Gem.pre_install do
      false
    end

    use_ui @ui do
      e = assert_raises Gem::InstallError do
        @installer.install
      end

      location = "#{__FILE__}:#{__LINE__ - 9}"

      assert_equal "pre-install hook at #{location} failed for a-2", e.message
    end

    spec_file = File.join @gemhome, 'specifications', @spec.spec_name
    refute File.exist? spec_file
  end

  def test_install_pre_install_nil
    util_clear_gems

    Gem.pre_install do
      nil
    end

    use_ui @ui do
      @installer.install
    end

    spec_file = File.join @gemhome, 'specifications', @spec.spec_name
    assert File.exist? spec_file
  end

  def test_install_with_message
    @spec.post_install_message = 'I am a shiny gem!'

    use_ui @ui do
      path = Gem::Builder.new(@spec).build

      @installer = Gem::Installer.new path
      @installer.install
    end

    assert_match %r|I am a shiny gem!|, @ui.output
  end

  def test_install_wrong_ruby_version
    use_ui @ui do
      installer = Gem::Installer.new old_ruby_required
      e = assert_raises Gem::InstallError do
        installer.install
      end
      assert_equal 'old_ruby_required requires Ruby version = 1.4.6.',
                   e.message
    end
  end

  def test_install_wrong_rubygems_version
    spec = quick_spec 'old_rubygems_required', '1' do |s|
      s.required_rubygems_version = '< 0'
    end

    util_build_gem spec

    gem = File.join(@gemhome, 'cache', spec.file_name)

    use_ui @ui do
      @installer = Gem::Installer.new gem
      e = assert_raises Gem::InstallError do
        @installer.install
      end
      assert_equal 'old_rubygems_required requires RubyGems version < 0. ' +
        "Try 'gem update --system' to update RubyGems itself.", e.message
    end
  end

  def test_installation_satisfies_dependency_eh
    dep = Gem::Dependency.new 'a', '>= 2'
    assert @installer.installation_satisfies_dependency?(dep)

    dep = Gem::Dependency.new 'a', '> 2'
    refute @installer.installation_satisfies_dependency?(dep)
  end

  def test_shebang
    util_make_exec @spec, "#!/usr/bin/ruby"

    shebang = @installer.shebang 'executable'

    assert_equal "#!#{Gem.ruby}", shebang
  end

  def test_shebang_arguments
    util_make_exec @spec, "#!/usr/bin/ruby -ws"

    shebang = @installer.shebang 'executable'

    assert_equal "#!#{Gem.ruby} -ws", shebang
  end

  def test_shebang_empty
    util_make_exec @spec, ''

    shebang = @installer.shebang 'executable'
    assert_equal "#!#{Gem.ruby}", shebang
  end

  def test_shebang_env
    util_make_exec @spec, "#!/usr/bin/env ruby"

    shebang = @installer.shebang 'executable'

    assert_equal "#!#{Gem.ruby}", shebang
  end

  def test_shebang_env_arguments
    util_make_exec @spec, "#!/usr/bin/env ruby -ws"

    shebang = @installer.shebang 'executable'

    assert_equal "#!#{Gem.ruby} -ws", shebang
  end

  def test_shebang_env_shebang
    util_make_exec @spec, ''
    @installer.env_shebang = true

    shebang = @installer.shebang 'executable'

    env_shebang = "/usr/bin/env" unless Gem.win_platform?

    assert_equal("#!#{env_shebang} #{Gem::ConfigMap[:ruby_install_name]}",
                 shebang)
  end

  def test_shebang_nested
    util_make_exec @spec, "#!/opt/local/ruby/bin/ruby"

    shebang = @installer.shebang 'executable'

    assert_equal "#!#{Gem.ruby}", shebang
  end

  def test_shebang_nested_arguments
    util_make_exec @spec, "#!/opt/local/ruby/bin/ruby -ws"

    shebang = @installer.shebang 'executable'

    assert_equal "#!#{Gem.ruby} -ws", shebang
  end

  def test_shebang_version
    util_make_exec @spec, "#!/usr/bin/ruby18"

    shebang = @installer.shebang 'executable'

    assert_equal "#!#{Gem.ruby}", shebang
  end

  def test_shebang_version_arguments
    util_make_exec @spec, "#!/usr/bin/ruby18 -ws"

    shebang = @installer.shebang 'executable'

    assert_equal "#!#{Gem.ruby} -ws", shebang
  end

  def test_shebang_version_env
    util_make_exec @spec, "#!/usr/bin/env ruby18"

    shebang = @installer.shebang 'executable'

    assert_equal "#!#{Gem.ruby}", shebang
  end

  def test_shebang_version_env_arguments
    util_make_exec @spec, "#!/usr/bin/env ruby18 -ws"

    shebang = @installer.shebang 'executable'

    assert_equal "#!#{Gem.ruby} -ws", shebang
  end

  def test_unpack
    util_setup_gem

    dest = File.join @gemhome, 'gems', @spec.full_name

    @installer.unpack dest

    assert File.exist?(File.join(dest, 'lib', 'code.rb'))
    assert File.exist?(File.join(dest, 'bin', 'executable'))
  end

  def test_write_spec
    spec_dir = File.join @gemhome, 'specifications'
    spec_file = File.join spec_dir, @spec.spec_name
    FileUtils.rm spec_file
    refute File.exist?(spec_file)

    @installer.spec = @spec
    @installer.gem_home = @gemhome

    @installer.write_spec

    assert File.exist?(spec_file)
    assert_equal @spec, eval(File.read(spec_file))
  end

  def test_write_spec_writes_cached_spec
    spec_dir = File.join @gemhome, 'specifications'
    spec_file = File.join spec_dir, @spec.spec_name
    FileUtils.rm spec_file
    refute File.exist?(spec_file)

    @spec.files = %w[a.rb b.rb c.rb]

    @installer.spec = @spec
    @installer.gem_home = @gemhome

    @installer.write_spec

    # cached specs have no file manifest:
    @spec.files = []

    assert_equal @spec, eval(File.read(spec_file))
  end

  def test_dir
    assert_match @installer.dir, %r!/installer/gems/a-2$!
  end

  def old_ruby_required
    spec = quick_spec 'old_ruby_required', '1' do |s|
      s.required_ruby_version = '= 1.4.6'
    end

    util_build_gem spec

    spec.cache_file
  end

  def util_execless
    @spec = quick_spec 'z'
    util_build_gem @spec

    @installer = util_installer @spec, @gemhome
  end

  def mask
    0100755 & (~File.umask)
  end
end
