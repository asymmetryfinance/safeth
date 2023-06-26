import { ethers, network } from "hardhat";
import { votiumMultiMerkleStashAbi } from "./abi/votiumMerkleStashAbi";

// These tests are for us to gain a better understanding of how the claim process works with merkle trees
// Claim will ultimately be called by our contract but first we need to understand the fundamentals.
describe.only("VotiumMerkleAccountClaim", async function () {
  // claimer for https://etherscan.io/tx/0xf31af41d8d572a6fc6845b631ab4a1ce469104d8dd0e57944960fd4e32e56da2
  const votiumClaimer = "0x3C1f89de9834b6c2F5a98E0bC2540439256656e5";

  const votiumMultiMerkleStashAddress =
    "0x378ba9b73309be80bf4c2c027aad799766a7ed5a";

  before(async () => {
    await network.provider.request({
      method: "hardhat_reset",
      params: [
        {
          forking: {
            jsonRpcUrl: process.env.MAINNET_URL,
            blockNumber: Number(17447306), // block number for https://etherscan.io/tx/0xf31af41d8d572a6fc6845b631ab4a1ce469104d8dd0e57944960fd4e32e56da2
          },
        },
      ],
    });
  });
  it("Should impersonate an account that can claim at a specific block and claim using merkle tree data.", async function () {
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [votiumClaimer],
    });
    const claimerSigner = await ethers.getSigner(votiumClaimer);
    const votiumMultiMerkleStash = new ethers.Contract(
      votiumMultiMerkleStashAddress,
      votiumMultiMerkleStashAbi,
      claimerSigner
    );

    const token = "0x3432b6a60d23ca0dfca7761b7ab56459d9c964d0";
    const index = "807";
    const account = "0x3c1f89de9834b6c2f5a98e0bc2540439256656e5";
    const amount = "297114812891068366848";
    const merkleProof = [
      "0x5765c08649a570fe5a7ac6ba9d2e7684a58b7d0da778e6fd6cdaab7e4198c92d",
      "0x37598f5704f3485e7cb81d6c401bc15f7072934e5667253f7dcf72b71b84b6ac",
      "0x8df0fc67d4618b4c0a62f187ee9c7fa515468995e324282dc0994e1eb0e82d0e",
      "0x1012295b45a78e90ecb7fbc3d29f16d6fddf715d6d3260256c0838c0317a0beb",
      "0x3cdcf93321fd42506ff3c92c9b576c72c1e0feeffd42c61a558cd21894257a6c",
      "0xe33b6b440c5b2909be537015095af65ebb46ba6e343f269b6c2977d239305748",
      "0xe228ff6388e39682b35314278a459a951166103a01105bf0b031c4dd928dba75",
      "0xbe24ee860dc3f474b8b00273b02fdd7a90b9af207dc12f05f8fcd97bd19942d3",
      "0x638f7b9038907b5d617fc0a54bedd625b418dbc8c038ac7ffadadeb7c8feba01",
      "0xd3639395729fbf967cdbb022359ae03674a4029a46df67d72bcaf8babb7b236a",
      "0x306aa0c5fa53072ea9f739991f44cd7ead4dc2a1f6f592792f7646fe4aeb9c42",
      "0xf98355d99d451a1cf05f5ecdbc3f143214c9e00305ba02464affc7ef8e29c28a",
    ];

    const claimArgs = [token, index, account, amount, merkleProof];

    await votiumMultiMerkleStash.claim(...claimArgs);
  });
});
