const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const networks = require("../ios/skadnetwork.json");
const root = path.resolve(__dirname, "../..");
const testPublisher = "ca-app-pub-3940256099942544";

module.exports = { adUnits, prepareAds };

function adUnits(mode) {
	return Object.fromEntries(
		Object.entries({
			banner: "2435281174",
			interstitial: "4411468910",
			rewarded: "1712485313",
		}).map(([format, testId]) => [
			format,
			mode === "Release"
				? productionId(`ACODE_IOS_ADMOB_${format.toUpperCase()}_ID`, "/")
				: `${testPublisher}/${testId}`,
		]),
	);
}

function prepareAds(mode) {
	const appId =
		mode === "Release"
			? productionId("ACODE_IOS_ADMOB_APP_ID", "~")
			: process.env.ACODE_IOS_ADMOB_APP_ID || `${testPublisher}~1458002511`;
	adUnits(mode);
	const file = path.join(root, ".ios-build/App-Info.plist");
	fs.mkdirSync(path.dirname(file), { recursive: true });
	execFileSync("plutil", [
		"-convert",
		"xml1",
		"-o",
		file,
		path.join(root, "platforms/ios/runner/Info.plist"),
	]);
	for (const [key, value] of Object.entries({
		GADApplicationIdentifier: appId,
		GADDelayAppMeasurementInit: true,
		NSUserTrackingUsageDescription:
			"Your permission helps show relevant ads that support the free version of Acode.",
		SKAdNetworkItems: networks.map((id) => ({ SKAdNetworkIdentifier: id })),
	})) {
		execFileSync("plutil", [
			"-insert",
			key,
			"-json",
			JSON.stringify(value),
			file,
		]);
	}
}

function productionId(name, separator) {
	const value = process.env[name] || "";
	const pattern = new RegExp(`^ca-app-pub-\\d{16}${separator}\\d{10}$`);
	if (!pattern.test(value) || value.startsWith(testPublisher)) {
		throw new Error(
			`Set ${name} to the production iOS AdMob ID for free release builds.`,
		);
	}
	return value;
}
