import { defineConfig } from 'wxt';

// One source, three targets: Chrome/Edge/Brave (MV3 service worker), Firefox (MV3 event page) and Safari
// (bundled into TriwardenSafari.appex by Xcode). The version comes from package.json.
export default defineConfig({
  modules: ['@wxt-dev/module-solid'],
  manifestVersion: 3,
  manifest: ({ browser }) => ({
    name: 'Triwarden',
    description: 'Fill and save logins from your Triwarden vault. Filling asks for Touch ID in the app.',
    icons: { 48: 'icon-48.png', 96: 'icon-96.png', 128: 'icon-128.png' },
    permissions: ['nativeMessaging'],
    ...(browser === 'firefox' && {
      browser_specific_settings: {
        gecko: {
          // Permanent once published on addons.mozilla.org, and the host manifest's allowed_extensions must match it.
          id: 'triwarden@sinhong2011.github.io',
          // data_collection_permissions only exists from Firefox 140; older versions would reject the manifest.
          strict_min_version: '140.0',
          // The extension itself collects nothing; page URLs only go to the local app.
          data_collection_permissions: { required: ['none'] },
        },
      },
    }),
  }),
});
