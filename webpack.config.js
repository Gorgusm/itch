const { HotModuleReplacementPlugin } = require("webpack");

const TsconfigPathsPlugin = require("tsconfig-paths-webpack-plugin");
const HardSourceWebpackPlugin = require("hard-source-webpack-plugin");
const HappyPack = require("happypack");
const WebpackBuildNotifierPlugin = require("webpack-build-notifier");
const HtmlWebpackPlugin = require("html-webpack-plugin");
const CleanWebpackPlugin = require("clean-webpack-plugin");

const path = require("path");
const merge = require("webpack-merge");

module.exports = (env) => {
  return [
    merge.smart(getCommonConfig("main", env), {
      target: "electron-main",
      entry: {
        main: "./src/main/index.ts",
        "inject-game": "./src/main/inject/inject-game.ts",
        "inject-captcha": "./src/main/inject/inject-captcha.ts",
      },
      externals: [
        "bindings"
      ],
      plugins: [
        new CleanWebpackPlugin(["dist/main"]),
        new WebpackBuildNotifierPlugin({
          title: "itch (main)",
        }),
      ],
    }),
    merge.smart(getCommonConfig("renderer", env), {
      target: "electron-renderer",
      entry: {
        renderer: "./src/renderer/index.tsx",
      },
      externals: [
        "systeminformation",
      ],
      module: {
        rules: [
          {
            test: /\.(png|svg|woff|woff2)$/,
            use: [
              { loader: "file-loader" },
            ],
          },
          {
            test: /\.css$/,
            use: [
              { loader: "style-loader" },
              { loader: "css-loader" },
            ],
          }
        ]
      },
      plugins: [
        new CleanWebpackPlugin(["dist/renderer"]),
        new HotModuleReplacementPlugin(),
        new WebpackBuildNotifierPlugin({
          title: "itch (renderer)",
        }),
        new HtmlWebpackPlugin({
          filename: "index.html",
          template: path.resolve(`./src/index.ejs`),
          minify: false,
        }),
      ]
    }),
  ]
};

function getCommonConfig(type, env) {
  const isProduction = env.mode === "production";
  const mode = isProduction ? "production" : "development";

  return {
    mode,
    devtool: "eval",
    node: {
      __dirname: !isProduction,
      __filename: !isProduction,
    },
    output: {
      filename: "[name].js",
      chunkFilename: "[name].bundle.js",
      libraryTarget: "commonjs2",
      path: path.resolve(`./dist/${type}`),
    },
    resolve: {
      extensions: [".ts", ".tsx", ".js"],
      plugins: [
        new TsconfigPathsPlugin({})
      ],
    },
    module: {
      rules: [
        {
          test: /\.tsx?$/,
          exclude: "/node_modules/",
          use: [
            { loader: "happypack/loader?id=ts" },
          ]
        },
        {
          test: /\.node$/,
          use: [
            { loader: "node-loader" },
          ],
        }
      ]
    },
    plugins: [
      new HardSourceWebpackPlugin(),
      new HappyPack({
        id: "ts",
        threads: 4,
        loaders: [
          {
            path: "ts-loader",
            query: { happyPackMode: true }
          }
        ]
      }),
    ],
    optimization: {
      minimize: false,
      minimizer: [],
    },
  }
}
