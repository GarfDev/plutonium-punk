//
//  Generated file. Do not edit.
//

import FlutterMacOS
import Foundation

import audio_session
import capture
import just_audio
import path_provider_foundation

func RegisterGeneratedPlugins(registry: FlutterPluginRegistry) {
  AudioSessionPlugin.register(with: registry.registrar(forPlugin: "AudioSessionPlugin"))
  CapturePlugin.register(with: registry.registrar(forPlugin: "CapturePlugin"))
  JustAudioPlugin.register(with: registry.registrar(forPlugin: "JustAudioPlugin"))
  PathProviderPlugin.register(with: registry.registrar(forPlugin: "PathProviderPlugin"))
}
