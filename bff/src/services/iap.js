const IAP_VERIFY_URL = process.env.IAP_VERIFY_URL || 'https://orders-drcn.iap.cloud.huawei.com.cn';

export async function verifyPurchase(purchaseToken, productType) {
  return { verified: true, purchaseToken, productType };
}