import { defineConfig } from "vite-plus"

export default defineConfig({
  // plugin/lib/ is vp pack output.
  lint: {
    ignorePatterns: ["plugin/lib/**"],
    options: {
      typeAware: true,
      typeCheck: true,
    },
  },
  fmt: {
    ignorePatterns: ["plugin/lib/**"],
    semi: false,
    printWidth: 100,
  },
  test: {
    include: ["src/**/*.test.ts"],
  },
  // One ES module per src/ module, imported by the QML as
  // `import "lib/<module>.mjs" as <Module>`. es2017: Quickshell's QML engine
  // rejects object spread and rest (ES2018), so they get compiled down.
  // scripts/bundle-check.sh loads every bundle in the real engine.
  pack: {
    entry: {
      layout: "src/layout/index.ts",
      selection: "src/selection/index.ts",
      hyprland: "src/hyprland/index.ts",
    },
    format: ["esm"],
    platform: "neutral",
    target: "es2017",
    outDir: "plugin/lib",
    fixedExtension: true,
    dts: false,
    clean: true,
  },
  staged: {
    "*.ts": "vp check --fix",
  },
})
