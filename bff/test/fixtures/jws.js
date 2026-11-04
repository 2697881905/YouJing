/**
 * 测试/探针共用的 JWS 构造工具。
 *
 * 用 bff/test/fixtures 里的自签三级证书链（EC P-256）现签 JWS，
 * 配合 process.env.IAP_ROOT_CERT_PATH=<测试根证书> 让 verifyJws 走完整验签路径。
 * 仅测试信任：真实进程默认信任 bff/certs/RootCaG2Ecdsa.cer，伪造链无效。
 */
import { existsSync, readFileSync } from 'node:fs';
import { sign } from 'node:crypto';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const HERE = dirname(fileURLToPath(import.meta.url));

/**
 * 私钥不入库（.gitignore），干净检出后这里按需现生成三级测试链。
 * 只在缺材料时跑一次 openssl，生成物与仓库里那套同构（同 subject/同 OID）。
 */
function ensureFixtureCerts() {
  const needed = ['iap-test-root.cer', 'iap-test-leaf.cer', 'iap-test-leaf.key'];
  if (needed.every((f) => existsSync(join(HERE, f)))) return;
  execFileSync('bash', [join(HERE, 'gen-test-certs.sh')], { stdio: 'inherit' });
}
ensureFixtureCerts();

/** 测试根证书路径（进程启动时设进 IAP_ROOT_CERT_PATH） */
export const TEST_ROOT_CERT_PATH = join(HERE, 'iap-test-root.cer');

/** PEM 里的 body 就是 DER 的标准 base64 —— x5c 官方要求的就是这个编码 */
function derB64(file) {
  const pem = readFileSync(join(HERE, file), 'utf8');
  return pem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
}

export function leafCertificate() {
  return derB64('iap-test-leaf.cer');
}

function b64url(str) {
  return Buffer.from(str, 'utf8').toString('base64url');
}

/**
 * 用叶子私钥现签一个合法 JWS。
 * @param {object} payload 任意 JSON 负载
 * @param {{keyFile?: string, chain?: [string,string,string]}} opts 负例注入点：
 *   keyFile 换签发私钥（不匹配叶子证书时验签必败），chain 可换成 x5c-nooid 等异形链
 */
export function makeJws(payload, opts = {}) {
  const chain = opts.chain || [
    derB64('iap-test-leaf.cer'),
    derB64('iap-test-inter.cer'),
    derB64('iap-test-root.cer')
  ];
  const header = { alg: 'ES256', typ: 'JWT', x5c: chain };
  const h = b64url(JSON.stringify(header));
  const p = b64url(JSON.stringify(payload));
  const signature = sign(
    'sha256',
    Buffer.from(`${h}.${p}`, 'utf8'),
    { key: readFileSync(join(HERE, opts.keyFile || 'iap-test-leaf.key'), 'utf8'), dsaEncoding: 'ieee-p1363' }
  );
  return `${h}.${p}.${signature.toString('base64url')}`;
}

/** 无 OID 叶子的异形链（leaf-nooid / inter / root），测 MISSING_OID 拦截 */
export function chainWithoutOid() {
  return [
    derB64('iap-test-leaf-nooid.cer'),
    derB64('iap-test-inter.cer'),
    derB64('iap-test-root.cer')
  ];
}

/** 官方 PurchaseOrderPayload 的最小真实形态 */
export function purchaseOrderPayload(overrides = {}) {
  return {
    environment: 'Production',
    purchaseOrderId: 'test-po-0001',
    purchaseToken: 'testptoken000000000000000000000000000000000000000000000001',
    applicationId: '6917619826312400726',
    productId: 'youjing_pass',
    productType: '1',
    purchaseTime: Date.now() - 60_000,
    price: 990,
    currency: 'CNY',
    countryCode: 'CN',
    signedTime: Date.now() - 60_000,
    ...overrides
  };
}

/** 官方 SubGroupStatusPayload 的最小真实形态（自动续期订阅状态） */
export function subscriptionStatusPayload(overrides = {}) {
  const status = {
    subGroupGenerationId: 'test-gen-1',
    subscriptionId: 'test-sub-1',
    purchaseToken: 'testptoken000000000000000000000000000000000000000000000002',
    status: '1',
    expiresTime: Date.now() + 30 * 24 * 3600 * 1000,
    lastPurchaseOrder: purchaseOrderPayload({
      purchaseOrderId: 'test-po-0002',
      purchaseToken: 'testptoken000000000000000000000000000000000000000000000002',
      productId: 'youjing_sub_monthly',
      productType: '2',
      price: 1990,
      duration: 'P1M',
      subGroupGenerationId: 'test-gen-1',
      subscriptionId: 'test-sub-1',
      subGroupId: 'test-sg-1'
    })
  };
  return {
    environment: 'Production',
    applicationId: '6917619826312400726',
    packageName: 'com.youjing.app',
    subGroupId: 'test-sg-1',
    lastSubscriptionStatus: status,
    ...overrides
  };
}

/** 官方 v3 服务端关键事件通知的 NotificationPayload 最小形态 */
export function notificationPayload(overrides = {}) {
  return {
    notificationType: 'DID_NEW_TRANSACTION',
    notificationSubtype: 'DID_RENEW',
    notificationRequestId: 'notif-req-0001',
    notificationMetaData: {
      environment: 'Production',
      applicationId: '6917619826312400726',
      packageName: 'com.youjing.app',
      type: 2,
      currentProductId: 'youjing_sub_monthly',
      purchaseToken: 'testptoken000000000000000000000000000000000000000000000002',
      purchaseOrderId: 'test-po-0002'
    },
    notificationVersion: 'v3',
    signedTime: Date.now() - 60_000,
    ...overrides
  };
}
