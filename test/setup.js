const { assert, expect } = require("chai");
const chai = require("chai");
const BN = require("bn.js");
const TestERC20 = artifacts.require("TestERC20");
const Factory = artifacts.require("Factory");
const FactoryRedeem = artifacts.require("FactoryRedeem");
const PrimeOption = artifacts.require("PrimeOption");
const PrimeRedeem = artifacts.require("PrimeRedeem");
const PrimePerpetual = artifacts.require("PrimePerpetual");
const PrimeFlash = artifacts.require("PrimeFlash");
const Weth = artifacts.require("WETH9");
const CTokenLike = artifacts.require("CTokenLike");
chai.use(require("chai-bn")(BN));
const constants = require("./constants");
const { MILLION_ETHER } = constants.VALUES;

const newERC20 = async (name, symbol, totalSupply) => {
    let erc20 = await TestERC20.new(name, symbol, totalSupply);
    return erc20;
};

const newWeth = async () => {
    let weth = await Weth.new();
    return weth;
};

const newFlash = async (tokenP) => {
    let flash = await PrimeFlash.new(tokenP);
    return flash;
};

const newOptionFactory = async () => {
    let factory = await Factory.new();
    let factoryRedeem = await FactoryRedeem.new(factory.address);
    await factory.initialize(factoryRedeem.address);
    return factory;
};

const newInterestBearing = async (underlying, name, symbol) => {
    let compound = await CTokenLike.new(underlying, name, symbol);
    return compound;
};

const newPrime = async (factory, tokenU, tokenS, base, price, expiry) => {
    await factory.deployOption(tokenU, tokenS, base, price, expiry);
    let id = await factory.getId(tokenU, tokenS, base, price, expiry);
    let prime = await PrimeOption.at(await factory.options(id));
    return prime;
};

const newRedeem = async (prime) => {
    let tokenR = await prime.tokenR();
    let redeem = await PrimeRedeem.at(tokenR);
    return redeem;
};

const newPerpetual = async (ctokenU, ctokenS, tokenP, receiver) => {
    let perpetual = await PrimePerpetual.new(
        ctokenU,
        ctokenS,
        tokenP,
        receiver
    );
    return perpetual;
};

const newPrimitive = async (
    factory,
    underlying,
    strike,
    base,
    price,
    expiry
) => {
    let tokenU = underlying;
    let tokenS = strike;

    let prime = await newPrime(
        factory,
        tokenU.address,
        tokenS.address,
        base,
        price,
        expiry
    );
    let redeem = await newRedeem(prime);

    const Primitive = {
        tokenU: tokenU,
        tokenS: tokenS,
        prime: prime,
        redeem: redeem,
    };
    return Primitive;
};

const approveToken = async (token, owner, spender) => {
    await token.approve(spender, MILLION_ETHER, { from: owner });
};

module.exports = {
    newERC20,
    newWeth,
    newPrime,
    newRedeem,
    newFlash,
    newPerpetual,
    newOptionFactory,
    newInterestBearing,
    newPrimitive,
    approveToken,
};