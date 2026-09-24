import fs from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import { afterEach, expect, test, vi } from "vitest";

const require = createRequire(import.meta.url);
const { getAppConfig } = require("../../dev/config.js");
const { parseOptions } = require("../../dev/scripts/android.js");
const { parseOptions: parseIOSOptions } = require("../../dev/scripts/ios.js");
const packagePath = path.resolve(import.meta.dirname, "../../package.json");

afterEach(() => vi.restoreAllMocks());

test.each([
	["com.foxdebug.acode", "paid"],
	["com.foxdebug.acodefree", "free"],
])("selects %s from package.json for build and dev", (name, variant) => {
	const readFile = fs.readFileSync;
	vi.spyOn(fs, "readFileSync").mockImplementation((file, ...args) =>
		file === packagePath ? JSON.stringify({ name }) : readFile(file, ...args),
	);
	expect(getAppConfig()).toEqual({ targetId: name, variant });
	expect(parseOptions(["android", "prod", "bundle", "fdroid", "--target=device"])).toMatchObject({
		targetId: name, variant, mode: "p", bundle: true, channel: "fdroid", target: "device",
	});
	expect(parseIOSOptions(["ios", "prod", "--target=simulator"])).toMatchObject({
		targetId: name, variant, mode: "Release", target: "simulator", device: false,
	});

});

test.each(["free", "paid", "fdroid", "apk", "bundle"])("rejects Android-only %s arguments for iOS", (argument) => {
	expect(() => parseIOSOptions(["ios", argument])).toThrow(/For iOS/);
});

test("rereads package identity after an edit and rejects unsupported package names", () => {
	const readFile = fs.readFileSync;
	let name = "com.foxdebug.acode";
	vi.spyOn(fs, "readFileSync").mockImplementation((file, ...args) =>
		file === packagePath ? JSON.stringify({ name }) : readFile(file, ...args),
	);
	expect(parseOptions([]).variant).toBe("paid");
	name = "com.foxdebug.acodefree";
	expect(parseOptions([]).variant).toBe("free");
	name = "invalid.package";
	expect(() => parseOptions([])).toThrow(/package.json name/);
});

test.each(["free", "paid", "FREE", "PAID"])("rejects the removed %s argument instead of silently building a different edition", (argument) => {
	expect(() => parseOptions([argument, "dev", "apk"])).toThrow(/package.json name/);
});
