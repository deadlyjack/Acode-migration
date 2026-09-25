const fs = require("node:fs");
const path = require("node:path");
const ID_PAID = "com.foxdebug.acode";
const ID_FREE = "com.foxdebug.acodefree";

module.exports = { getAppConfig, getWebBundlePath };

function getAppConfig(platform = process.env.ACODE_PLATFORM || "android") {
	const { androidPackageId, appleAppId } = JSON.parse(
		fs.readFileSync(path.resolve(__dirname, "../package.json"), "utf8"),
	);
	if (platform === "ios") return { variant: "free", targetId: appleAppId };
	if (![ID_PAID, ID_FREE].includes(androidPackageId)) {
		throw new Error(
			`Set package.json androidPackageId to ${ID_PAID} (paid) or ${ID_FREE} (free).`,
		);
	}
	return {
		variant: androidPackageId === ID_FREE ? "free" : "paid",
		targetId: androidPackageId,
	};
}

function getWebBundlePath(platform = process.env.ACODE_PLATFORM || "android") {
	return path.resolve(
		__dirname,
		"..",
		platform === "ios"
			? "platforms/ios/runner/bundle"
			: "platforms/android/app/src/main/assets/bundle",
	);
}
