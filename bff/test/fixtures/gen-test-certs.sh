#!/usr/bin/env bash
# 生成三级 EC(P-256) 测试证书链，供 bff/test/fixtures/jws.js 现签 JWS。
#
# 只建立「测试信任」：生产进程信任的是 bff/certs/RootCaG2Ecdsa.cer（华为真根证书），
# 用这里生成的根签不出来收据一律 ROOT_MISMATCH/BAD_CHAIN。
# 私钥不入库（.gitignore 排除 *.key/*.srl），干净检出后 npm test 会自动调用本脚本补齐。
#
# 用法：bash bff/test/fixtures/gen-test-certs.sh
set -euo pipefail
cd "$(dirname "$0")"
command -v openssl >/dev/null || { echo "需要 openssl（macOS 自带 / Xcode 工具链）" >&2; exit 1; }

CFG="$(mktemp)"
trap 'rm -f "$CFG" iap-test-*.csr' EXIT

# 叶子必须带 OID 1.3.6.1.4.1.2011.2.415.1.1（iapJws.js 的 MISSING_OID 判据）
cat > "$CFG" <<'CNF'
[req]
distinguished_name = dn
prompt = no
[dn]
C = CN
O = Youjing Test
[root_ca]
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
[inter_ca]
basicConstraints = critical, CA:TRUE, pathlen:0
keyUsage = critical, keyCertSign, cRLSign
[leaf]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
1.3.6.1.4.1.2011.2.415.1.1 = critical, DER:05:00
[leaf_nooid]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
CNF

newkey() { openssl ecparam -name prime256v1 -genkey -noout -out "$1"; }

# npm test 是多进程并行跑的：谁先发现缺材料谁生成，其余进程拿到锁时必须跳过，
# 否则两条链交错落盘（根来自 A、叶子来自 B）会让 verifyJws 随机报 BAD_CHAIN。
LOCK_DIR="$PWD/.gen.lock"
waited=0
while ! mkdir "$LOCK_DIR" 2>/dev/null; do
  sleep 0.2
  waited=$((waited + 1))
  if [ "$waited" -gt 300 ]; then echo "等锁超时：$LOCK_DIR" >&2; exit 1; fi
done
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT
if [ -f iap-test-leaf.key ] && [ -f iap-test-root.cer ]; then
  echo "测试证书链已在位，跳过生成"
  exit 0
fi

newkey iap-test-root.key
openssl req -new -x509 -key iap-test-root.key -out iap-test-root.cer \
  -days 3650 -sha256 -config "$CFG" -extensions root_ca \
  -subj "/C=CN/O=Youjing Test/CN=Test IAP Root CA"

newkey iap-test-inter.key
openssl req -new -key iap-test-inter.key -out iap-test-inter.csr \
  -config "$CFG" -subj "/C=CN/O=Youjing Test/CN=Test IAP Intermediate CA"
openssl x509 -req -in iap-test-inter.csr -CA iap-test-root.cer -CAkey iap-test-root.key \
  -CAcreateserial -out iap-test-inter.cer -days 3000 -sha256 \
  -extfile "$CFG" -extensions inter_ca

newkey iap-test-leaf.key
openssl req -new -key iap-test-leaf.key -out iap-test-leaf.csr \
  -config "$CFG" -subj "/C=CN/O=Youjing Test/CN=Test IAP Leaf"
openssl x509 -req -in iap-test-leaf.csr -CA iap-test-inter.cer -CAkey iap-test-inter.key \
  -CAcreateserial -out iap-test-leaf.cer -days 3000 -sha256 \
  -extfile "$CFG" -extensions leaf

# 无 OID 的异形叶子：只为验 MISSING_OID 拦截，不参与正对照
newkey iap-test-leaf-nooid.key
openssl req -new -key iap-test-leaf-nooid.key -out iap-test-leaf-nooid.csr \
  -config "$CFG" -subj "/C=CN/O=Youjing Test/CN=Test IAP Leaf No OID"
openssl x509 -req -in iap-test-leaf-nooid.csr -CA iap-test-inter.cer -CAkey iap-test-inter.key \
  -CAcreateserial -out iap-test-leaf-nooid.cer -days 3000 -sha256 \
  -extfile "$CFG" -extensions leaf_nooid

rm -f iap-test-*.srl
echo "测试证书链已生成于 $(pwd)（*.key 不入库）"
