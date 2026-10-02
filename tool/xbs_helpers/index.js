import {parse} from 'parse5';
import {DOMImplementation, XMLSerializer} from '@xmldom/xmldom';
import xpath from 'xpath';
import md5 from 'blueimp-md5';
import {Base64} from 'js-base64';

// This bundle is pure computation. It has no network, file or device access.
const serializer = new XMLSerializer();
function appendNode(source, parent, doc, budget) {
  if (--budget.remaining < 0) throw new Error('XBS HTML node limit exceeded');
  if (source.nodeName === '#text') {
    parent.appendChild(doc.createTextNode(source.value));
    return;
  }
  if (!source.tagName) return;
  const element = doc.createElement(source.tagName);
  for (const attr of source.attrs || []) element.setAttribute(attr.name, attr.value);
  parent.appendChild(element);
  for (const child of source.childNodes || []) appendNode(child, element, doc, budget);
}

function parseHtml(source) {
  const value = String(source ?? '');
  if (value.length > 2 * 1024 * 1024) throw new Error('XBS HTML size limit exceeded');
  const doc = new DOMImplementation().createDocument(null, null, null);
  const budget = {remaining: 50000};
  for (const child of parse(value).childNodes) appendNode(child, doc, doc, budget);
  return wrapNode(doc);
}

function query(node, expression) {
  let context = node;
  // XBS field selectors use // relative to the current list item, including it.
  if (node.nodeType === 1 && expression.startsWith('//')) {
    context = new DOMImplementation().createDocument(null, null, null);
    context.appendChild(context.importNode(node, true));
  }
  const selected = xpath.select(expression, context);
  return (Array.isArray(selected) ? selected : [selected]).map(wrapNode);
}

function wrapNode(node) {
  const content = () => typeof node === 'object' ? (node.textContent ?? node.nodeValue ?? '') : String(node);
  const raw = () => typeof node === 'object' ? serializer.serializeToString(node) : String(node);
  return {
    queryWithXPath: expression => query(node, String(expression)),
    content,
    raw,
    toJSON: raw,
    toString: content,
  };
}

const noop = () => {};
globalThis.console = Object.freeze(Object.fromEntries(
  ['log','info','debug','warn','error','trace','exception','table','assert','clear','time','timeEnd'].map(key => [key, noop])
));
globalThis.__xbsCreateNativeTool = (cache, changes) => ({
  log: noop,
  logWithKey: noop,
  getCache: key => Object.prototype.hasOwnProperty.call(cache, String(key)) ? cache[String(key)] : null,
  setCache: (key, value) => {
    key = String(key);
    if (key.length > 1024) throw new Error('XBS cache key too long');
    const encoded = JSON.stringify(value ?? null);
    if (encoded.length > 128 * 1024 || changes.length >= 256) throw new Error('XBS cache limit exceeded');
    Object.defineProperty(cache, key, {value: JSON.parse(encoded), writable:true, configurable:true, enumerable:true});
    changes.push([key, JSON.parse(encoded)]);
  },
  md5Encode: value => md5(String(value)),
  base64Encode: value => Base64.encode(String(value)),
  base64Decode: value => Base64.decode(String(value)),
  Base64DecodeToString: value => Base64.decode(String(value)),
  stringByObject: value => JSON.stringify(value),
  XPathParserWithSource: parseHtml,
});
