#!/usr/bin/env ruby
# Local preflight only: does not upload, accept agreements or verify public URL availability.
require 'json'
require 'uri'

root = File.expand_path('..', __dir__)
errors = []
metadata = JSON.parse(File.read(File.join(root, 'docs/app-store/metadata.json')))
expected = %w[en-US ru uk]
errors << 'Store languages must be exactly en-US, ru, uk' unless metadata.keys.sort == expected.sort
metadata.each do |language, fields|
  { 'name' => 30, 'subtitle' => 30, 'promotionalText' => 170, 'keywords' => 100, 'description' => 4000 }.each do |field, limit|
    value = fields[field]
    errors << "#{language}/#{field}: blank or exceeds #{limit} characters" unless value.is_a?(String) && !value.strip.empty? && value.length <= limit
  end
end
%w[en ru uk].each do |language|
  %w[terms privacy authors sources].each do |page|
    path = File.join(root, 'Legal', language, "#{page}.md")
    errors << "Missing legal document: #{language}/#{page}" unless File.file?(path) && File.size(path) > 500
  end
end
config = JSON.parse(File.read(File.join(root, 'docs/app-store/release-config.json')))
project = File.read(File.join(root, 'Lad.xcodeproj/project.pbxproj'))
%w[MARKETING_VERSION CURRENT_PROJECT_VERSION].zip(%w[version build]).each do |setting, field|
  errors << "#{setting} does not match release-config.json" unless project.include?("#{setting} = #{config[field]};")
end
errors << 'Legal resources missing from Xcode project' unless project.include?('/* Legal in Resources */')
release_exclusions = project.scan(/EXCLUDED_SOURCE_FILE_NAMES\s*=\s*(\([^;]*\)|[^;]+);/m).flatten.join("\n")
errors << 'Legacy recipe bodies must be excluded from Release resources' unless release_exclusions.include?('legacy-recipes.json')
unless ARGV.include?('--content-only')
  unless config['adMobAppId'].to_s.match?(/\Aca-app-pub-\d+~\d+\z/) &&
         config['adMobBannerId'].to_s.match?(/\Aca-app-pub-\d+\/\d+\z/) &&
         !config['adMobAppId'].include?('3940256099942544')
    errors << 'Configure publisher AdMob app/banner IDs before publishing; the beta SDK identifier is for testing only.'
  end
  %w[publisherLegalName copyrightHolder].each do |key|
    errors << "Required publisher decision: #{key}" unless config[key].is_a?(String) && !config[key].strip.empty?
  end
  %w[supportEmail privacyEmail authorContactEmail].each do |key|
    errors << "Required valid contact: #{key}" unless config[key].is_a?(String) && config[key].match?(/\A[^\s@]+@[^\s@]+\.[^\s@]+\z/)
  end
  %w[privacyPolicyURL supportURL].each do |key|
    begin
      url = URI.parse(config[key].to_s)
      valid = url.is_a?(URI::HTTPS) && url.host && !url.host.end_with?('example.com', 'example.org', 'localhost') && !url.userinfo
    rescue URI::InvalidURIError
      valid = false
    end
    errors << "Required real public HTTPS URL: #{key}" unless valid
  end
end
if errors.empty?
  puts(ARGV.include?('--content-only') ? 'Local copy/version checks passed; publication prerequisites not checked.' : 'Local preflight passed. Manual release checklist, rights/privacy and public URL checks still required.')
else
  warn errors.map { |error| "- #{error}" }.join("\n")
  exit 1
end
