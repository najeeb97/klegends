import assert from 'node:assert/strict';
import {test} from 'node:test';
import {normalizePhone,safeReturnUrl} from '../src/phone.ts';
for(const [country,input,expected] of [
  ['+91','98765 43210','+919876543210'],['+91','+91 98765 43210','+919876543210'],
  ['+971','050 123 4567','+971501234567'],['+966','00566',null],['+966','+966 50 123 4567','+966501234567'],
  ['+974','5512 3456','+97455123456'],['+968','9212 3456','+96892123456'],
  ['+965','5512 3456','+96555123456'],['+973','3312 3456','+97333123456'],
  ['+91','123',null],['+91','1234567890',null],['+971','+91 98765 43210',null],
  ['+91','abc9876543210',null],['+91','9876543210 ext 1',null],['+971','00971 50 123 4567','+971501234567'],
  ['+91','98765432100',null],['+971','++971501234567',null],['+91','',null]
]) test(`phone ${country} ${input}`,()=>assert.equal(normalizePhone(country,input),expected));
for(const input of ['https://example.com','//example.com','/\\example.com','/\n/evil'])
  test(`unsafe return ${JSON.stringify(input)}`,()=>assert.equal(safeReturnUrl(input),'/'));
test('match return preserved',()=>assert.equal(safeReturnUrl('/m/abc?invite=x'),'/m/abc?invite=x'));
