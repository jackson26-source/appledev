import { registerPlugin } from '@capacitor/core';

export interface SharedTextPlugin {
  /** Reads and clears whatever text was last shared in via the Share Extension. */
  consume(): Promise<{ text: string | null }>;
}

export const SharedText = registerPlugin<SharedTextPlugin>('SharedText');
