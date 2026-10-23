import { createHash } from 'node:crypto';

// Assemble the pinned engine with SpringNote's boot entry and selection accessor.
export function buildRenderer(source, inventory) {
  const hash = createHash('sha256').update(source).digest('hex');
  if (hash !== inventory.frame.sha256) throw new Error('Engine source checksum mismatch');
const entry = inventory.frame.modules.find(m => m.id === 'a');
const expose = `$__System.registerDynamic("springnote",${JSON.stringify(inventory.frame.modules.map(m => m.id))},true,function(require,exports,module){
window.springNoteModules=require;window.$=window.jQuery=require("e");
window.fastdom=require("b").extend(require("c"));require("d");require("f");require("10");
window.NFile=window.File;window.File=require("47");window.CodeMirror=require("20");module.exports={};
});`;
// Keep the original editing algorithms; add a host entry and a position accessor.
const sourceView = inventory.frame.modules.find(m => m.id === '3a');
const mapperExposure = 'i.prototype.getMarkdownPosition=C;';
if (!source.slice(sourceView.start, sourceView.end).endsWith('n.exports=i})')) throw new Error('SourceView signature changed');
const sourceWithMapper = source.slice(0, sourceView.end - 'n.exports=i})'.length) + mapperExposure + source.slice(sourceView.end - 'n.exports=i})'.length);
const renderer = (sourceWithMapper.slice(0, entry.start + mapperExposure.length) + expose + sourceWithMapper.slice(entry.start + mapperExposure.length))
  .replace('(["a"],[],!0,function', '(["springnote"],[],!0,function');
if (renderer === source || !renderer.includes('(["springnote"],[],!0,function')) throw new Error('Renderer entry signature changed');

return renderer;
}
