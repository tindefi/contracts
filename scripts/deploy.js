// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");

async function main() {
  provider = waffle.provider;

  //Token
  const Tindefi = await hre.ethers.getContractFactory("Tin_defi");
  tin = await Tindefi.deploy(21000000);

  await tin.deployed();

  console.log("Token: "+tin.address);


  console.log("Verifying contract");
  
  try{
      await hre.run("verify:verify", {
      address: tin.address,
      constructorArguments: [
        21000000,
      ],
    });

    console.log("Contract verified");
  }catch(e){console.log(e);}
  



  //VESTING
  let blockTimestamp = (await provider.getBlock("latest")).timestamp;
  const VESTING = await hre.ethers.getContractFactory("TokenVesting");
  vest = await VESTING.deploy(tin.address, blockTimestamp, 0, 1000, 60);

  await vest.deployed();

  console.log("Vesting: "+vest.address);


  console.log("Verifying contract");
  
  try{
      await hre.run("verify:verify", {
      address: vest.address,
      constructorArguments: [
        tin.address,
        blockTimestamp,
        0,
        1000,
        60,
      ],
    });

    console.log("Contract verified");
  }catch(e){}

  //BUSD Mainnet: 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56
  //ICO
  const ICO = await hre.ethers.getContractFactory("ICOTinDeFi");
  ico = await ICO.deploy(tin.address, vest.address, "0x34654fbCF8822BAd63c3715184d8AbDd8Eb70B00", "0xE5E2664c21E0Ff1c1a95DB09Bee3143223712919");

  await ico.deployed();

  console.log("ICO: "+ico.address);


  console.log("Verifying contract");
  

  try{
      
    await hre.run("verify:verify", {
      address: ico.address,
      constructorArguments: [
        tin.address,
        vest.address,
        "0x34654fbCF8822BAd63c3715184d8AbDd8Eb70B00",
        "0xE5E2664c21E0Ff1c1a95DB09Bee3143223712919",
      ],
    });

    console.log("Contract verified");
  }catch(e){}

  await vest.addAdmin(ico.address);

  //Config
  await tin.mint(vest.address, ethers.utils.parseEther("100000"));

  await ico.addPhaseParams(0, ethers.utils.parseEther("0.000000000000000001"), ethers.utils.parseEther("100000"));

  await ico.addReferral("normal", '0x33880a3093e1e3244dfa2c4f1e3976a41c403a68a9a46d658ad84540151881dd', "0xE5E2664c21E0Ff1c1a95DB09Bee3143223712919", 10, 10, 90);
  await ico.addReferral("capital", '0xbdc126fb66a19d5738edc1551662bd8be1886b6ce38e9fb3ce730d459fcdac1e', "0xE5E2664c21E0Ff1c1a95DB09Bee3143223712919", 10, 10, 90);

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
