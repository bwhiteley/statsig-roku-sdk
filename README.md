## Statsig Roku Client SDK

The Roku SDK for single user client environments. If you need a SDK for another language or server environment, check out our [other SDKs](https://docs.statsig.com/#sdks).

Statsig helps you move faster with feature gates (feature flags), and/or dynamic configs. It also allows you to run A/B/n tests to validate your new features and understand their impact on your KPIs. If you're new to Statsig, check out our product and create an account at [statsig.com](https://www.statsig.com).

## Getting Started
Check out our [SDK docs](https://docs.statsig.com/client/rokuSDK) to get started.

## Parameter Stores

The Roku SDK supports Statsig Parameter Stores.

```brightscript
homepageStore = statsig.getParameterStore("homepage")

title = homepageStore.getString("title", "Welcome")
showUpsell = homepageStore.getBoolean("upsell_upgrade_now", false)
maxTiles = homepageStore.getNumber("max_tiles", 6)
```
