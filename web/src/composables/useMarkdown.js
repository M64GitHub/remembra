import { marked } from 'marked'
import DOMPurify from 'dompurify'
import hljs from 'highlight.js/lib/core'

// Core languages
import javascript from 'highlight.js/lib/languages/javascript'
import typescript from 'highlight.js/lib/languages/typescript'
import python from 'highlight.js/lib/languages/python'
import json from 'highlight.js/lib/languages/json'
import bash from 'highlight.js/lib/languages/bash'
import css from 'highlight.js/lib/languages/css'
import xml from 'highlight.js/lib/languages/xml'
import sql from 'highlight.js/lib/languages/sql'
import markdown from 'highlight.js/lib/languages/markdown'

// Systems languages
import go from 'highlight.js/lib/languages/go'
import rust from 'highlight.js/lib/languages/rust'
import c from 'highlight.js/lib/languages/c'
import cpp from 'highlight.js/lib/languages/cpp'

// Register core languages
hljs.registerLanguage('javascript', javascript)
hljs.registerLanguage('js', javascript)
hljs.registerLanguage('typescript', typescript)
hljs.registerLanguage('ts', typescript)
hljs.registerLanguage('python', python)
hljs.registerLanguage('py', python)
hljs.registerLanguage('json', json)
hljs.registerLanguage('bash', bash)
hljs.registerLanguage('sh', bash)
hljs.registerLanguage('shell', bash)
hljs.registerLanguage('css', css)
hljs.registerLanguage('html', xml)
hljs.registerLanguage('xml', xml)
hljs.registerLanguage('sql', sql)
hljs.registerLanguage('markdown', markdown)
hljs.registerLanguage('md', markdown)

// Register systems languages
hljs.registerLanguage('go', go)
hljs.registerLanguage('golang', go)
hljs.registerLanguage('rust', rust)
hljs.registerLanguage('rs', rust)
hljs.registerLanguage('c', c)
hljs.registerLanguage('cpp', cpp)
hljs.registerLanguage('c++', cpp)

// Zig is not in highlight.js core, register as plaintext fallback
hljs.registerLanguage('zig', () => ({
  name: 'Zig',
  keywords: {
    keyword: [
      'align', 'allowzero', 'and', 'anyframe', 'anytype', 'asm',
      'async', 'await', 'break', 'catch', 'comptime', 'const',
      'continue', 'defer', 'else', 'enum', 'errdefer', 'error',
      'export', 'extern', 'fn', 'for', 'if', 'inline', 'noalias',
      'nosuspend', 'null', 'opaque', 'or', 'orelse', 'packed',
      'pub', 'resume', 'return', 'struct', 'suspend', 'switch',
      'test', 'threadlocal', 'try', 'undefined', 'union',
      'unreachable', 'usingnamespace', 'var', 'volatile', 'while'
    ].join(' '),
    literal: 'true false null undefined',
    built_in: [
      'u8', 'u16', 'u32', 'u64', 'u128', 'usize',
      'i8', 'i16', 'i32', 'i64', 'i128', 'isize',
      'f16', 'f32', 'f64', 'f128',
      'bool', 'void', 'anyerror', 'anyopaque', 'anytype',
      'comptime_int', 'comptime_float', 'noreturn', 'type'
    ].join(' ')
  },
  contains: [
    hljs.C_LINE_COMMENT_MODE,
    hljs.C_BLOCK_COMMENT_MODE,
    {
      className: 'string',
      begin: '"',
      end: '"',
      contains: [{ begin: '\\\\.' }]
    },
    {
      className: 'string',
      begin: "'",
      end: "'"
    },
    {
      className: 'number',
      begin: '\\b(0x[0-9a-fA-F_]+|0b[01_]+|0o[0-7_]+|[0-9][0-9_]*)',
      relevance: 0
    },
    {
      className: 'function',
      beginKeywords: 'fn',
      end: '\\(',
      excludeEnd: true,
      contains: [
        {
          className: 'title',
          begin: '[a-zA-Z_][a-zA-Z0-9_]*'
        }
      ]
    },
    {
      className: 'type',
      begin: '@[a-zA-Z_][a-zA-Z0-9_]*'
    }
  ]
}))

function highlightCode(code, lang) {
  if (lang && hljs.getLanguage(lang)) {
    try {
      return hljs.highlight(code, { language: lang }).value
    } catch (e) {
      console.warn('Highlight error:', e)
    }
  }
  try {
    return hljs.highlightAuto(code).value
  } catch (e) {
    return escapeHtml(code)
  }
}

function escapeHtml(text) {
  const div = document.createElement('div')
  div.textContent = text
  return div.innerHTML
}

// Custom renderer for subtle headers and code blocks with copy button
const renderer = new marked.Renderer()

renderer.code = function ({ text, lang }) {
  const langLabel = lang || 'text'
  const highlighted = highlightCode(text, lang)
  const encodedCode = encodeURIComponent(text)
  return '<div class="md-code-block" data-language="' + langLabel + '">' +
    '<div class="md-code-header">' +
    '<span class="md-code-lang">' + escapeHtml(langLabel) + '</span>' +
    '<button class="md-code-copy" data-code="' + encodedCode + '">Copy</button>' +
    '</div>' +
    '<pre><code class="hljs">' + highlighted + '</code></pre>' +
    '</div>'
}

renderer.link = function ({ href, title, text }) {
  const titleAttr = title ? ` title="${escapeHtml(title)}"` : ''
  return `<a href="${escapeHtml(href)}"${titleAttr} ` +
    `target="_blank" rel="noopener noreferrer">${text}</a>`
}

// Configure marked
marked.setOptions({
  gfm: true,
  breaks: false,
  renderer: renderer
})

// DOMPurify configuration - allow necessary tags
const purifyConfig = {
  ALLOWED_TAGS: [
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
    'p', 'br', 'hr',
    'ul', 'ol', 'li',
    'blockquote',
    'pre', 'code',
    'table', 'thead', 'tbody', 'tr', 'th', 'td',
    'a', 'strong', 'em', 's', 'del',
    'div', 'span', 'button'
  ],
  ALLOWED_ATTR: [
    'class', 'style', 'href', 'target', 'rel', 'title',
    'data-language', 'data-code'
  ],
  ALLOW_DATA_ATTR: true
}

export function useMarkdown() {
  function renderMarkdown(content) {
    if (!content) return ''
    const html = marked.parse(content)
    return DOMPurify.sanitize(html, purifyConfig)
  }

  return { renderMarkdown }
}
