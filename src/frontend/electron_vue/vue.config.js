module.exports = {
  configureWebpack: {
    // Configuration applied to all builds
  },
  pluginOptions: {
    electronBuilder: {
      nodeIntegration: true,
      mainProcessWatch: [],
      mainProcessArgs: [],
      builderOptions: {
        appId: "com.novocurrency.app",
        productName: "Novo",
        extraFiles: [],
        publish: null,
        "afterSign": "@oshell/vue-cli-plugin-electron-builder-notarize",
        "mac": {
          "category": "public.app-category.finance",
          "asar": false,
          "hardenedRuntime": true
        },
        "win": {
          "sign": "./sign.js"
        },
        "linux": {
          "category": "public.app-category.finance"
        }
      }
    },
    i18n: {
      locale: "en",
      fallbackLocale: "en",
      localeDir: "locales",
      enableInSFC: false
    }
  },
  css: {
    loaderOptions: {
      less: {
        javascriptEnabled: true
      }
    }
  }
};