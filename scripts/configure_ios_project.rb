#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Runs in CI, after `npx cap add ios` has generated ios/App/App.xcodeproj
# from Capacitor's own template. Does everything a person would otherwise
# click through in Xcode by hand:
#
#   1. Adds our two native Swift files (native TTS + shared-text bridge) to
#      the main App target.
#   2. Creates the "CitolexShare" Share Extension target, adds its files,
#      and embeds it into the main app.
#   3. Turns on the App Group entitlement (group.com.citolex.app) on both
#      targets, so they can hand text to each other.
#
# Background audio (Background Modes > Audio) is deliberately NOT enabled
# here — see the note above the Info.plist block below. Read-aloud stops
# when the app is backgrounded/screen-locked, by design.
#
# Requires the `xcodeproj` gem, which ships already installed alongside
# CocoaPods on GitHub's macOS runners — no extra install step needed.
#
# This is scripted best-effort against Capacitor's documented project
# layout. If a specific `xcodeproj` gem call errors out in your CI run
# (project structure can shift between Capacitor versions), paste the
# error back and it can be patched — this is much cheaper to fix than
# doing the whole thing by hand in Xcode.

require 'xcodeproj'
require 'fileutils'

ROOT = File.expand_path('..', __dir__)
PROJECT_PATH = File.join(ROOT, 'ios/App/App.xcodeproj')
APP_GROUP_ID = 'group.com.citolex.app'
BUNDLE_ID_APP = 'com.citolex.app'
BUNDLE_ID_SHARE = 'com.citolex.app.share'
APPLE_TEAM_ID = ENV.fetch('APPLE_TEAM_ID', '8N6W89UUA5')
# App Store Connect silently rejects re-uploads that reuse the same
# marketing version + build number pair (the *file transfer* still reports
# success via altool either way, which is why this can look fine in the CI
# log while the build never actually shows up in TestFlight). Every CI run
# gets a unique build number from GitHub's own per-workflow run counter, so
# every push produces an installable build.
BUILD_NUMBER = ENV.fetch('BUILD_NUMBER', '1')

# MARKETING_VERSION (CFBundleShortVersionString, e.g. "1.1.0") is the OTHER
# half of that uniqueness pair, and until 2026-08-25 nothing here ever set
# it — `npx cap add ios` regenerates the Xcode project from Capacitor's
# template every run, and its default MARKETING_VERSION ("1.0") was never
# overridden, so every build stayed "1.0" forever regardless of BUILD_NUMBER
# or package.json's own version field. That's harmless right up until the
# "1.0" App Store version actually goes Ready for Distribution — at which
# point Apple closes that version's TestFlight "pre-release train" entirely,
# and altool starts rejecting every future upload with "Invalid Pre-Release
# Train... closed for new build submissions" while still exiting 0, so it
# read as a green checkmark in CI for hours before anyone noticed. Reading
# package.json here keeps one single source of truth for the app's version —
# bump package.json's "version" and both the CI-visible number and the
# actual binary agree.
require 'json'
PACKAGE_JSON_PATH = File.join(ROOT, 'package.json')
APP_VERSION = JSON.parse(File.read(PACKAGE_JSON_PATH)).fetch('version', '1.0.0')

abort "Xcode project not found at #{PROJECT_PATH} — run `npx cap add ios` first." unless File.exist?(PROJECT_PATH)

project = Xcodeproj::Project.open(PROJECT_PATH)
app_target = project.targets.find { |t| t.name == 'App' }
abort 'Could not find the "App" target — Capacitor template may have changed.' unless app_target

app_src_dir = File.join(ROOT, 'ios/App/App')
FileUtils.mkdir_p(app_src_dir)

# ---------------------------------------------------------------------------
# 1. Copy in + reference the native plugin Swift files on the main target
# ---------------------------------------------------------------------------
%w[NativeTtsPlugin.swift SharedTextPlugin.swift].each do |fname|
  src = File.join(ROOT, 'ios-plugin', fname)
  dst = File.join(app_src_dir, fname)
  FileUtils.cp(src, dst)
  file_ref = project.main_group.new_file(dst)
  app_target.add_file_references([file_ref])
  puts "Added #{fname} to App target"
end

# ---------------------------------------------------------------------------
# 2. App Group entitlement + Background Audio mode on the main app
# ---------------------------------------------------------------------------
app_entitlements_path = File.join(app_src_dir, 'App.entitlements')
File.write(app_entitlements_path, <<~PLIST)
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
      <key>com.apple.security.application-groups</key>
      <array>
          <string>#{APP_GROUP_ID}</string>
      </array>
  </dict>
  </plist>
PLIST

app_target.build_configurations.each do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'App/App.entitlements'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = BUNDLE_ID_APP
  config.build_settings['CODE_SIGN_STYLE'] = 'Manual'
  config.build_settings['CODE_SIGN_IDENTITY'] = 'Apple Distribution'
  config.build_settings['DEVELOPMENT_TEAM'] = APPLE_TEAM_ID
  config.build_settings['PROVISIONING_PROFILE_SPECIFIER'] = 'Citolex App Store'
  config.build_settings['CURRENT_PROJECT_VERSION'] = BUILD_NUMBER
  config.build_settings['MARKETING_VERSION'] = APP_VERSION
end

# Background audio was previously enabled here (UIBackgroundModes =
# ['audio']) so read-aloud could keep going with the screen locked or the
# app backgrounded. That's explicitly not wanted anymore — the app should
# stop playing as soon as it's backgrounded — so this now actively removes
# the key instead of setting it, in case an older cached/regenerated
# Info.plist (or a future Capacitor template) already has it set. Without
# this entitlement, iOS suspends the app's audio session on background the
# same way it would for any other non-audio app, which is what we want.
info_plist_path = File.join(app_src_dir, 'Info.plist')
if File.exist?(info_plist_path)
  plist = Xcodeproj::Plist.read_from_path(info_plist_path)
  if plist.delete('UIBackgroundModes')
    puts 'Removed UIBackgroundModes from Info.plist (background audio disabled)'
  else
    puts 'UIBackgroundModes already absent from Info.plist — background audio stays disabled'
  end
  Xcodeproj::Plist.write_to_path(plist, info_plist_path)
else
  warn "Warning: #{info_plist_path} not found — background audio should stay disabled by default (Capacitor's template doesn't set UIBackgroundModes), but worth confirming in Xcode if this script's Info.plist path guess was wrong."
end

# ---------------------------------------------------------------------------
# 3. Create the Share Extension target
# ---------------------------------------------------------------------------
share_dir = File.join(ROOT, 'ios/App/CitolexShare')
FileUtils.mkdir_p(share_dir)
FileUtils.cp(File.join(ROOT, 'ios-share-extension/ShareViewController.swift'), File.join(share_dir, 'ShareViewController.swift'))
FileUtils.cp(File.join(ROOT, 'ios-share-extension/Info.plist'), File.join(share_dir, 'Info.plist'))

share_entitlements_path = File.join(share_dir, 'CitolexShare.entitlements')
File.write(share_entitlements_path, <<~PLIST)
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
      <key>com.apple.security.application-groups</key>
      <array>
          <string>#{APP_GROUP_ID}</string>
      </array>
  </dict>
  </plist>
PLIST

share_target = project.new_target(:app_extension, 'CitolexShare', :ios, '14.0')

share_file_refs = project.main_group.new_file(File.join(share_dir, 'ShareViewController.swift'))
share_target.add_file_references([share_file_refs])

share_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_NAME'] = 'CitolexShare'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = BUNDLE_ID_SHARE
  config.build_settings['INFOPLIST_FILE'] = 'CitolexShare/Info.plist'
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'CitolexShare/CitolexShare.entitlements'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  config.build_settings['CODE_SIGN_STYLE'] = 'Manual'
  config.build_settings['CODE_SIGN_IDENTITY'] = 'Apple Distribution'
  config.build_settings['DEVELOPMENT_TEAM'] = APPLE_TEAM_ID
  config.build_settings['PROVISIONING_PROFILE_SPECIFIER'] = 'Citolex Share App Store'
  config.build_settings['CURRENT_PROJECT_VERSION'] = BUILD_NUMBER
  config.build_settings['MARKETING_VERSION'] = APP_VERSION
end

# Also record manual signing + team in the project's TargetAttributes, which
# is where Xcode itself (and some xcodebuild paths) look for provisioning
# style — belt and suspenders alongside the build settings above.
project.root_object.attributes['TargetAttributes'] ||= {}
[app_target, share_target].each do |t|
  project.root_object.attributes['TargetAttributes'][t.uuid] ||= {}
  project.root_object.attributes['TargetAttributes'][t.uuid]['ProvisioningStyle'] = 'Manual'
  project.root_object.attributes['TargetAttributes'][t.uuid]['DevelopmentTeam'] = APPLE_TEAM_ID
end

# ---------------------------------------------------------------------------
# 4. Embed the extension into the main app (Xcode's "Embed App Extensions"
#    copy-files build phase) and wire up the target dependency
# ---------------------------------------------------------------------------
app_target.add_dependency(share_target)

embed_phase = app_target.copy_files_build_phases.find { |p| p.name == 'Embed App Extensions' }
embed_phase ||= app_target.new_copy_files_build_phase('Embed App Extensions')
embed_phase.symbol_dst_subfolder_spec = :plug_ins
embed_phase.add_file_reference(share_target.product_reference, true)
build_file = embed_phase.files_references.include?(share_target.product_reference) &&
             embed_phase.files.find { |f| f.file_ref == share_target.product_reference }
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] } if build_file

project.save
puts "\nDone. Share extension target 'CitolexShare' created and embedded."
puts 'If any step above warned or looks off once you inspect the build log, that is the part worth double-checking first.'
