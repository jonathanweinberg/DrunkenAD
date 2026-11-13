require 'fileutils'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'yaml'

# Exercise the actual YAML run blocks. Never inherit credentials, load a
# publishing module, or substitute a real Gallery endpoint for the recorder.
class GalleryWorkflowTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  FILE = File.join(ROOT, '.github/workflows/powershell-gallery.yml')
  KEY = %q{offline-only-'"`$(); & sentinel}
  CHECKOUT = 'actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683'

  def setup
    @flow = YAML.safe_load(File.read(FILE))
    @validate, @publish = @flow.fetch('jobs').values_at('validate', 'publish')
    @tmp = Dir.mktmpdir
    FileUtils.cp_r(File.join(ROOT, 'DrunkenAD'), @tmp)
    @manifest = File.join(@tmp, 'DrunkenAD/DrunkenAD.psd1')
    File.write(@manifest, File.read(@manifest).sub(/ModuleVersion\s*= '[^']+'/,
                                                   "ModuleVersion = '1.2.3'"))
  end

  def teardown
    FileUtils.remove_entry(@tmp) if @tmp
  end

  def run_step(job, ref, env = {})
    script = job.fetch('steps').last.fetch('run')
    harness = <<~'POWERSHELL'
      $ErrorActionPreference = 'Stop'
      Import-Module Microsoft.PowerShell.Management, Microsoft.PowerShell.Utility
      $PSModuleAutoLoadingPreference = 'None'
      function Publish-Module {
          [CmdletBinding()] param($Path, $Repository, $NuGetApiKey)
          if ($NuGetApiKey -cne $env:EXPECTED_FAKE_KEY -or $Repository -cne 'PSGallery' -or
              (Resolve-Path $Path).Path -ne (Resolve-Path ./DrunkenAD).Path) { throw 'Incorrect publish arguments' }
          Add-Content -LiteralPath ./calls -Value 'called'
          if ($env:SIMULATE_FAILURE) { throw "Synthetic error containing $NuGetApiKey" }
      }
    POWERSHELL
    clean = {'PATH' => ENV.fetch('PATH'), 'HOME' => @tmp, 'TMPDIR' => @tmp,
             'GITHUB_REF' => ref, 'GITHUB_OUTPUT' => File.join(@tmp, 'outputs'),
             'EXPECTED_FAKE_KEY' => KEY, 'POWERSHELL_TELEMETRY_OPTOUT' => '1'}
    log, status = Open3.capture2e(clean.merge(env), 'pwsh', '-NoProfile', '-NonInteractive',
                                 '-Command', harness + script, chdir: @tmp, unsetenv_others: true)
    refute_includes log, KEY
    [log, status.success?]
  end

  def test_only_new_tag_pushes_can_reach_a_protected_job
    assert_equal({'push' => {'tags' => ['v*']}}, @flow.fetch('on'))
    assert_equal({'contents' => 'read'}, @flow.fetch('permissions'))
    assert_equal %w[publish validate], @flow.fetch('jobs').keys.sort
    assert_equal 'github.event.created && !github.event.deleted', @validate.fetch('if')
    assert_equal 'validate', @publish.fetch('needs')
    assert_equal "needs.validate.outputs.eligible == 'true'", @publish.fetch('if')
    gate = @validate.fetch('steps').last.fetch('id')
    assert_equal "${{ steps.#{gate}.outputs.eligible }}", @validate.fetch('outputs').fetch('eligible')
    assert_equal 'powershell-gallery', @publish.fetch('environment')
    [@validate, @publish].each do |job|
      checkout, step = job.fetch('steps')
      assert_equal 2, job.fetch('steps').size
      assert_equal CHECKOUT, checkout.fetch('uses')
      assert_equal({'ref' => '${{ github.sha }}', 'persist-credentials' => false}, checkout.fetch('with'))
      assert_equal 'pwsh', step.fetch('shell')
      refute_includes step.fetch('run'), '${{'
    end
    assert_equal({'PSGALLERY_API_KEY' => '${{ secrets.PSGALLERY_API_KEY }}',
                  'PSGALLERY_PUBLISH_TAG' => '${{ vars.PSGALLERY_PUBLISH_TAG }}'},
                 @publish.fetch('steps').last.fetch('env'))
    assert_equal 1, File.read(FILE).scan(/secrets\./i).size
  end

  def test_exact_matching_version_is_eligible
    log, ok = run_step(@validate, 'refs/tags/v1.2.3')
    assert ok, log
    assert_equal ['eligible=true'], File.readlines(File.join(@tmp, 'outputs'), chomp: true)
  end

  def test_wrong_version_branch_and_noncanonical_tag_fail_closed
    %w[refs/tags/v1.2.4 refs/heads/v1.2.3 refs/tags/V1.2.3 refs/tags/v1.2.3-rc1].each do |ref|
      _, ok = run_step(@validate, ref)
      refute ok, ref
      refute File.exist?(File.join(@tmp, 'outputs'))
    end
  end

  def test_matching_014_tag_is_held_before_secret_job
    File.write(@manifest, File.read(@manifest).sub("ModuleVersion = '1.2.3'", "ModuleVersion = '0.14.0'"))
    log, ok = run_step(@validate, 'refs/tags/v0.14.0')
    assert ok, log
    assert_match(/::notice::.*0\.14/, log)
    assert_equal ['eligible=false'], File.readlines(File.join(@tmp, 'outputs'), chomp: true)
  end

  def test_no_key_and_blank_key_notice_without_publishing
    [nil, '   '].each do |key|
      log, ok = run_step(@publish, 'refs/tags/v1.2.3', 'PSGALLERY_API_KEY' => key,
                         'PSGALLERY_PUBLISH_TAG' => 'v1.2.3')
      assert ok, log
      assert_match(/::notice::.*PSGALLERY_API_KEY.*skip/i, log)
      refute File.exist?(File.join(@tmp, 'calls'))
    end
  end

  def test_a_key_alone_or_another_authorized_tag_cannot_publish
    [nil, 'v1.2.4'].each do |allowed|
      log, ok = run_step(@publish, 'refs/tags/v1.2.3', 'PSGALLERY_API_KEY' => KEY,
                         'PSGALLERY_PUBLISH_TAG' => allowed)
      assert ok, log
      assert_match(/::notice::.*skip/i, log)
      refute File.exist?(File.join(@tmp, 'calls'))
    end
  end

  def test_explicitly_authorized_tag_passes_opaque_key_once_to_recorder
    log, ok = run_step(@publish, 'refs/tags/v1.2.3', 'PSGALLERY_API_KEY' => KEY,
                       'PSGALLERY_PUBLISH_TAG' => 'v1.2.3')
    assert ok, log
    assert_equal ['called'], File.readlines(File.join(@tmp, 'calls'), chomp: true)
  end

  def test_publisher_error_is_sanitized_and_not_retried
    _, ok = run_step(@publish, 'refs/tags/v1.2.3', 'PSGALLERY_API_KEY' => KEY,
                     'PSGALLERY_PUBLISH_TAG' => 'v1.2.3', 'SIMULATE_FAILURE' => '1')
    refute ok
    assert_equal ['called'], File.readlines(File.join(@tmp, 'calls'), chomp: true)
  end
end
