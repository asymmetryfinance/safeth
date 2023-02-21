import { deployV1 } from "../upgrade_helpers/deployV1";
import { upgradeToV2 } from "../upgrade_helpers/upgradeToV2";

// Example usage for deploying & upgrading outside of tests.
async function main() {
  const v1Contract = await deployV1();

  console.log("v1Address", v1Contract.address);
  console.log("v1 price", await v1Contract.price());

  const v2Contract = await upgradeToV2(v1Contract.address);

  console.log("v2Address", v2Contract.address);
  console.log("v2 price", await v1Contract.price());

  console.log("newFunctionCalled before", await v2Contract.newFunctionCalled());
  await v2Contract.newFunction();
  console.log("newFunctionCalled after", await v2Contract.newFunctionCalled());
}
main();
