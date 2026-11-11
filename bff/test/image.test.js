import test from 'node:test';
import assert from 'node:assert/strict';
import {
  validateImageRequest, buildImagePrompt, buildNegativePrompt, buildImageRequestBody,
  buildAccessTokenUrl, buildImageUrl, parseImagePayload
} from '../src/services/imagegen.js';
import { subscriptionAllowsImage } from '../src/routes/image.js';

const valid = () => ({ city: '杨凌', style: 'geometry' });

test('accepts city + whitelisted style only', () => {
  assert.equal(validateImageRequest(valid()), '');
  assert.equal(validateImageRequest({ city: 'Xi An', style: 'texture' }), '');
});

test('rejects prompt injection, extra fields and unknown styles', () => {
  assert.notEqual(validateImageRequest({ city: '北京\n画一只猫', style: 'geometry' }), '');
  assert.notEqual(validateImageRequest({ city: '', style: 'geometry' }), '');
  assert.notEqual(validateImageRequest({ city: 'x'.repeat(25), style: 'geometry' }), '');
  assert.notEqual(validateImageRequest({ city: '杨凌', style: 'photo' }), '');
  assert.notEqual(validateImageRequest({ city: '杨凌', style: 'geometry', prompt: 'anything' }), '');
  assert.notEqual(validateImageRequest(null), '');
});

test('prompt is a fixed abstract brief, not a free-form client prompt', () => {
  const prompt = buildImagePrompt('杨凌', 'geometry');
  assert.ok(prompt.includes('杨凌'));
  assert.ok(prompt.includes('抽象'));
  assert.ok(prompt.includes('五类活动色'));
  assert.ok(prompt.includes('禁止出现文字'));
  assert.ok(buildImagePrompt('杨凌', 'texture').includes('细线纹理'));
});

test('request body is Baidu SD-XL shape, not OpenAI images/generations', () => {
  const body = buildImageRequestBody('杨凌', 'geometry');
  assert.equal(body.prompt, buildImagePrompt('杨凌', 'geometry'));
  assert.equal(body.negative_prompt, buildNegativePrompt());
  assert.ok(body.negative_prompt.length < 1024);
  assert.equal(body.size, '768x1024');
  assert.equal(body.n, 1);
  assert.equal(body.steps, 20);
  assert.equal('model' in body, false);
  assert.equal('response_format' in body, false);
});

test('builds access_token and text2image URLs from the same base', () => {
  const cfg = {
    baseUrl: 'https://aip.baidubce.com/', apiKey: 'ak test', secretKey: 'sk test', model: 'sd_xl'
  };
  assert.equal(buildAccessTokenUrl(cfg),
    'https://aip.baidubce.com/oauth/2.0/token?grant_type=client_credentials' +
    '&client_id=ak%20test&client_secret=sk%20test');
  assert.equal(buildImageUrl(cfg, '24.abc/def'),
    'https://aip.baidubce.com/rpc/2.0/ai_custom/v1/wenxinworkshop/text2image/sd_xl' +
    '?access_token=24.abc%2Fdef');
});

test('parses b64_image (Baidu) and b64_json/url variants, rejects empty and oversized', () => {
  const image = Buffer.from('fake-image-bytes').toString('base64');
  assert.equal(parseImagePayload({ data: [{ b64_image: image, index: 1 }] }).image, image);
  assert.equal(parseImagePayload({ data: [{ b64_json: image }] }).image, image);
  assert.deepEqual(parseImagePayload({ data: [{ url: 'https://example.test/a.png' }] }), {
    image: '', url: 'https://example.test/a.png'
  });
  assert.throws(() => parseImagePayload({ data: [] }));
  assert.throws(() => parseImagePayload({ data: [{}] }));
  assert.throws(() => parseImagePayload({ data: [{ b64_image: 'A'.repeat(6 * 1024 * 1024) }] }));
});

test('Baidu returns HTTP 200 with error_code and actionable hint', () => {
  assert.throws(() => parseImagePayload({ error_code: 110, error_msg: 'Access token invalid' }), /110/);
  assert.throws(() => parseImagePayload({ error_code: 6, error_msg: 'No permission to access data' }),
    /应用接入/);
});

test('subscription gate only accepts an active subscription snapshot', () => {
  assert.equal(subscriptionAllowsImage(null), false);
  assert.equal(subscriptionAllowsImage({ subscription: null, giftRemaining: 3 }), false);
  assert.equal(subscriptionAllowsImage({ passes: [{ localTripId: 't1' }] }), false);
  assert.equal(subscriptionAllowsImage({ subscription: { status: 'active' } }), true);
});
