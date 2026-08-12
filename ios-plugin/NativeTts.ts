import { registerPlugin } from '@capacitor/core';

export interface NativeTtsVoice {
  identifier: string;
  name: string;
  language: string;
}

export interface SpeakOptions {
  text: string;
  rate?: number;      // 0.1 - 2.0, matches the web speechSynthesis scale roughly
  voiceId?: string;    // identifier from listVoices()
}

export interface NativeTtsPlugin {
  listVoices(): Promise<{ voices: NativeTtsVoice[] }>;
  speak(options: SpeakOptions): Promise<void>;
  pause(): Promise<void>;
  resume(): Promise<void>;
  stop(): Promise<void>;
  addListener(
    eventName: 'boundary',
    listenerFunc: (data: { charIndex: number }) => void
  ): Promise<{ remove: () => void }>;
  addListener(
    eventName: 'finish',
    listenerFunc: () => void
  ): Promise<{ remove: () => void }>;
}

/**
 * Native on-device TTS via AVSpeechSynthesizer. Falls back gracefully —
 * callers should check Capacitor.isNativePlatform() and use the browser's
 * window.speechSynthesis on web, exactly like citolex.com already does.
 */
export const NativeTts = registerPlugin<NativeTtsPlugin>('NativeTts');
