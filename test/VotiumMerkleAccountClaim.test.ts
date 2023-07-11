import { ethers, network } from "hardhat";
import { votiumMultiMerkleStashAbi } from "./abi/votiumMerkleStashAbi";
import ERC20 from "@openzeppelin/contracts/build/contracts/ERC20.json";
import { expect } from "chai";

// These tests are for us to gain a better understanding of how the claim process works with merkle trees
// Claim will ultimately be called by our contract but first we need to understand the fundamentals.
describe.only("VotiumMerkleAccountClaim", async function () {
  const votiumMultiMerkleStashAddress =
    "0x378ba9b73309be80bf4c2c027aad799766a7ed5a";
  const fxsTokenAddress = "0x3432b6a60d23ca0dfca7761b7ab56459d9c964d0";
  const cvxTokenAddress = "0x4e3fbd56cd56c3e72c1403e103b45db9da5b9d2b";
  const usddTokenAddress = "0x0c10bf8fcb7bf5412187a595ab97a3609160b5c6";

  it.only("Should impersonate an account that can claim (single) at a specific block and claim using merkle tree data.", async function () {
    // claimer for https://etherscan.io/tx/0xf31af41d8d572a6fc6845b631ab4a1ce469104d8dd0e57944960fd4e32e56da2
    const votiumSingleClaimer = "0x8a65ac0E23F31979db06Ec62Af62b132a6dF4741";

    await network.provider.request({
      method: "hardhat_reset",
      params: [
        {
          forking: {
            jsonRpcUrl: process.env.MAINNET_URL,
            blockNumber: Number(17671000), // block number before https://etherscan.io/tx/0xf31af41d8d572a6fc6845b631ab4a1ce469104d8dd0e57944960fd4e32e56da2
          },
        },
      ],
    });

    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [votiumSingleClaimer],
    });
    const claimerSigner = await ethers.getSigner(votiumSingleClaimer);
    const votiumMultiMerkleStash = new ethers.Contract(
      votiumMultiMerkleStashAddress,
      votiumMultiMerkleStashAbi,
      claimerSigner
    );

    const token = "0x3432b6a60d23ca0dfca7761b7ab56459d9c964d0";
    const index = "1979";
    const amount = "1112337167376589";
    const merkleProof = [
      "0x18bac82463aa912d6aa6ac03115529c1c5620ea129ff929d4c55b06faee598a7",
      "0x76a2dceefde1630b3ec07facfd5e10142c5e3c73155034519e0c9f5dbe23ec93",
      "0xe99f4c087a1a90b80eef269382c1ebc96cdfb7089a0fa1d8c78113accc74a1d4",
      "0xabfbf2702f7627efc9f014e993f45e8cd4491ea1ee18a25c123854b9f58e6a0e",
      "0x5c38612ced3664afba1d238dfff35e7da3a53092143b84eec84e38ebf6934136",
      "0x02733ad9bce8db3c6ea08ff5cc4cdb2033e4b022653ea1b8132f41fa1593db6d",
      "0x43ba09e7f507683daa5f4cd6df3c6f6fc0b50fc2e2bcbdeef6d7ebc28d5fdd37",
      "0xe2c0521263d498e0e8804c0d76f1a26546067d913e78a9adb5d3ae661b89c0b4",
      "0x3eedc7747ed7c54a9124f8a15b0f58caaf3159529281cba6034ebf78c1740154",
      "0xd0c96c43161bfdc06de2933af08910006d189e5db4c8f6053c6d145f6fd0a37b",
      "0x2e6d8cead919efb391a6ba85dff0a3bc28034a98117aa21b97ca203e172bda4f",
      "0x1d078cc2169d7b238323e9756b3e285f469ae4e130ed82df6fb4755bb3bce2e4",
    ];

    const claimArgs = [token, index, votiumSingleClaimer, amount, merkleProof];

    const fxsContract = new ethers.Contract(
      fxsTokenAddress,
      ERC20.abi,
      claimerSigner
    );
    const fxsBalanceBefore = await fxsContract.balanceOf(votiumSingleClaimer);
    const tx = await votiumMultiMerkleStash.claim(...claimArgs);
    await tx.wait();
    const fxsBalanceAfter = await fxsContract.balanceOf(votiumSingleClaimer);
    expect(fxsBalanceAfter).gt(fxsBalanceBefore);
  });
  it("Should impersonate an account that can claim (multi) at a specific block and claim using merkle tree data.", async function () {
    const votiumMultiClaimer = "0x8a65ac0E23F31979db06Ec62Af62b132a6dF4741";

    await network.provider.request({
      method: "hardhat_reset",
      params: [
        {
          forking: {
            jsonRpcUrl: process.env.MAINNET_URL,
            blockNumber: Number(17556543), // block number before https://etherscan.io/tx/0x3aab41954fe3bb0dd14e1fb2cb5c7f3cc38a39791745592fc210468b27ca3037
          },
        },
      ],
    });

    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [votiumMultiClaimer],
    });
    const claimerSigner = await ethers.getSigner(votiumMultiClaimer);
    const votiumMultiMerkleStash = new ethers.Contract(
      votiumMultiMerkleStashAddress,
      votiumMultiMerkleStashAbi,
      claimerSigner
    );

    const token0 = "0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0";
    const index0 = "2846";
    const amount0 = "24328676021904990208";
    const merkleProof0 = [
      "0x0b2cb7733d30e573db967d856e8ac3982ff7835fbf76b6c79c315ef4ac46849a",
      "0xf2efb76e00d6e419b18ed85600e668b4b48e4da974aa88e7f4e6dbd5371ea0fd",
      "0x783bba3a65e9d38f8d2ac9de36ade64cd5acd413210dae8297078538df97516d",
      "0xc82156660bd6b85a0c54de4691a9ca5a8d6a4be5baa551a7b8f47b3b14a74293",
      "0x0c5aa6dd0f12dc1b1a0fca382b8eaefb62686631e41624bd6d1fad29c2b5bd59",
      "0x4a3c56399eec3853ba13c48aaeb33d1e7244b2e6366da3f23d012031e25b865b",
      "0x7e9012c197c8380555395b8937e253fd2d8b7a7d3fe580816ad8a18b12f7d25a",
      "0x75fd4dd6d706f1425c7f1aa94ba0ec9121362a8dd3b2daced2a680c67b273863",
      "0xa5883db78fbeb7480f886c02d129be4c9749f697b7bb4ff5174c782bf7b2e990",
      "0x44519f56f3883b76f3addb39af1e8c6b323e5c089a4e6c021593196a2df6b2a9",
      "0x1aaa3886f062e851c890f73c2cffadd37847752bbf05cf6409c89fbd491e2b26",
      "0x1dfd2e468f57818d4efc155b7e27a97b90920cb8dda5d404a331d7752aa9ab14",
    ];

    const token1 = "0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B";
    const index1 = "3162";
    const amount1 = "219881957970128666624";
    const merkleProof1 = [
      "0xfaacd5e42d02e6cdf7449a1541b7c28148ebb5e3f403a170acff844166bfad80",
      "0xd121ec9a3a89f8dccfed68810bd438d28683b090b7d48acf3de3af4c54fefe36",
      "0x29c41941731f5fc26a2af8516568c9bede4003a55df60f3e2a8b7587963f07e0",
      "0x5b11c7b70f02193f4deb16e67281c32d7a826c7a065c1b8d0ce4673720764b7f",
      "0xd3a531904e01b179f86289feee06ebdfce89ec767c2039c98e8202ec54e30e08",
      "0x2571f5040006b8960f387f6375b581e4ea2c21c18d5530f1675cd0a8aa272003",
      "0x6a9443452a0238d4f0be587f952a9953200ee71f71449cf5231d5a35523f16f4",
      "0x5ce4abef1476465726a8a4ea7770e1c495bbc3518cf895a12545baf9fca65843",
      "0x7d147c9c86bf28084e8c5ecb3879e07689327dafcaa14a5af6c9be2ddd41baaa",
      "0x88d2430b1810a6c7d72ec99223b782c325ddddec94c51cd4a1586cea3b32e6c8",
      "0x5790cc372c7a99cee63816b4e41c796be131778bbae6a14e7adb012831ee132e",
      "0xa7e517cb702a89a49b9c5e9d736c1ff9788382c9ae0286c6bf1ad358a0b45191",
    ];

    const token2 = "0x0C10bF8FcB7Bf5412187A595ab97a3609160b5c6";
    const index2 = "1470";
    const amount2 = "884323870258511872000";
    const merkleProof2 = [
      "0xfc0c0946f7041696662c350b7c3a1cd90cfa334f7506023446d778837e023fff",
      "0x7979549d5d26c9eeefdaf12a0d2c0071418cc37ba46ae4b2a462e4a810b783c8",
      "0xa3ba97bc2aee7a99c4e5de720b82e573ededb612ece94843e5ae9e6f4f210ad7",
      "0x38ef94cd2c7ed9ae21e7170482cac96d7567a643d80eed109bdce73ab2fdaf7b",
      "0xc291becb986819d20cfb9bedd910a82acfbcfc2c7574832a30732847a9324e7a",
      "0x17f8a1edf4a1f4dffc1bdb1456cbb565ad1c4a3cafedcb5f36f049ffd0090ace",
      "0xf4731fe6d104bf75a1e7a7be13bfd4232a5f99cb0077469f69655f5144c5ae3d",
      "0x54f1a18fe9d57accb781079e3929524781589a595536e307eddf61ed42515e99",
      "0x93330485cc3134380d1398f001e01c128fd8f197dcc33046605196c6b970fdda",
      "0x3dd57f5e061f9239016e5837b47389092a2a17a5f2b28e6fdefebc3f0807e748",
    ];

    const multiClaimArgs0 = [token0, index0, amount0, merkleProof0];
    const multiClaimArgs1 = [token1, index1, amount1, merkleProof1];
    const multiClaimArgs2 = [token2, index2, amount2, merkleProof2];

    const claimArgs = [multiClaimArgs0, multiClaimArgs1, multiClaimArgs2];

    const fxsContract = new ethers.Contract(
      fxsTokenAddress,
      ERC20.abi,
      claimerSigner
    );
    const cvxContract = new ethers.Contract(
      cvxTokenAddress,
      ERC20.abi,
      claimerSigner
    );
    const usddContract = new ethers.Contract(
      usddTokenAddress,
      ERC20.abi,
      claimerSigner
    );

    const fxsBalanceBefore = await fxsContract.balanceOf(votiumMultiClaimer);
    const cvxBalanceBefore = await cvxContract.balanceOf(votiumMultiClaimer);
    const usddBalanceBefore = await usddContract.balanceOf(votiumMultiClaimer);

    const tx = await votiumMultiMerkleStash.claimMulti(
      votiumMultiClaimer,
      claimArgs
    );
    await tx.wait();

    const fxsBalanceAfter = await fxsContract.balanceOf(votiumMultiClaimer);
    const cvxBalanceAfter = await cvxContract.balanceOf(votiumMultiClaimer);
    const usddBalanceAfter = await usddContract.balanceOf(votiumMultiClaimer);

    expect(fxsBalanceAfter).gt(fxsBalanceBefore);
    expect(cvxBalanceAfter).gt(cvxBalanceBefore);
    expect(usddBalanceAfter).gt(usddBalanceBefore);
  });
});
