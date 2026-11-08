/* Coco ERP — rounded, solid pictograms on a transparent 24px canvas.
   Original artwork inspired by the visual language of Upview Icons:
   generous curves, compact silhouettes and clear negative space.
   One inherited colour keeps every drawing usable in compact controls. */
const path=d=>'<path d="'+d+'" fill-rule="evenodd"/>';
const rect=(x,y,w,h,r=1.5)=>'<rect x="'+x+'" y="'+y+'" width="'+w+'" height="'+h+'" rx="'+r+'"/>';
const dot=(x,y,r)=>'<circle cx="'+x+'" cy="'+y+'" r="'+r+'"/>';
const line=(d,w=3)=>'<path d="'+d+'" fill="none" stroke="currentColor" stroke-width="'+w+'" stroke-linecap="round" stroke-linejoin="round"/>';
const roundRect=(x,y,w,h,r)=>'M'+(x+r)+' '+y+'h'+(w-2*r)+'a'+r+' '+r+' 0 0 1 '+r+' '+r+'v'+(h-2*r)+'a'+r+' '+r+' 0 0 1 -'+r+' '+r+'H'+(x+r)+'a'+r+' '+r+' 0 0 1 -'+r+' -'+r+'V'+(y+r)+'a'+r+' '+r+' 0 0 1 '+r+' -'+r+'Z';
const disc=(x,y,r)=>'M'+(x-r)+' '+y+'a'+r+' '+r+' 0 1 0 '+(2*r)+' 0a'+r+' '+r+' 0 1 0 -'+(2*r)+' 0Z';
const cog=(x,y,r)=>{
 const teeth=Array.from({length:6},(_,i)=>'<rect x="'+(x-r*.23)+'" y="'+(y-r)+'" width="'+(r*.46)+'" height="'+(r*.55)+'" rx="'+(r*.14)+'" transform="rotate('+(i*60)+' '+x+' '+y+')"/>').join('');
 return teeth+path(disc(x,y,r*.78)+disc(x,y,r*.31));
};

const artwork={
 workhub:path(roundRect(2,2,20,20,4)+roundRect(5,5,14,3,1)+roundRect(5,11,4,8,1)+roundRect(12,11,7,3,1)+roundRect(12,16,7,3,1)),
 home:path('M10.1 2.7a3 3 0 0 1 3.8 0l7 5.7a2 2 0 0 1-1.2 3.6H20v6a4 4 0 0 1-4 4h-1v-6a3 3 0 0 0-6 0v6H8a4 4 0 0 1-4-4v-6h.3a2 2 0 0 1-1.2-3.6Z'),
 chart:path('M9.5 2.3a1 1 0 0 1 1.2 1v10h10a1 1 0 0 1 1 1.2A10 10 0 1 1 9.5 2.3ZM14 2a8 8 0 0 1 8 8h-8Z'),
 sales:rect(2,14,5,8,2)+rect(9.5,9,5,13,2)+rect(17,2,5,20,2),
 cocoBot:path(roundRect(3,7,18,15,5)+roundRect(7,12,3,5,1.5)+roundRect(14,12,3,5,1.5))+rect(1,12,2,6,1)+rect(21,12,2,6,1)+rect(10.5,3,3,5,1.5)+dot(12,3,2),
 handshake:path('M9.5 4.5 12 6l-3.7 3.7a2.8 2.8 0 0 0 4 4l2.4-2.4 5.5 5.5-4.8 4a2.5 2.5 0 0 1-3.3-.1L5.5 15l-3.3-5a1.7 1.7 0 0 1 .2-2.2l3.5-3.4a2.8 2.8 0 0 1 3.6.1ZM13.4 5a2.8 2.8 0 0 1 3.4-.4l4.6 3a2 2 0 0 1 .6 2.7l-1.4 2.4-4-4a2.8 2.8 0 0 0-4 0l-2.2 2.2a.8.8 0 0 1-1.1-1.1Z'),
 cube:path('M10.9 2.3a2.5 2.5 0 0 1 2.2 0l7.1 3.6L12 10.3 3.8 5.9ZM2 8.3l8.5 4.4v9L3.4 18A2.5 2.5 0 0 1 2 15.8ZM22 8.3v7.5a2.5 2.5 0 0 1-1.4 2.2l-7.1 3.7v-9Z'),
 cart:path('M2.5 2a1.5 1.5 0 0 0 0 3h1l2.1 10a3 3 0 0 0 3 2.4h9a3 3 0 0 0 2.9-2.2L22 9a2 2 0 0 0-2-2.5H7L6.5 4a2.5 2.5 0 0 0-2.4-2ZM10 9h8v2.5h-8Z')+dot(9,21,2)+dot(18,21,2),
 warehouse:path('M10.3 2.7a3 3 0 0 1 3.4 0l7 4.7A3 3 0 0 1 22 10v8a4 4 0 0 1-4 4H6a4 4 0 0 1-4-4v-8a3 3 0 0 1 1.3-2.5ZM6 11v3h12v-3Zm0 6v5h12v-5Z'),
 truck:path('M4 4h8a2 2 0 0 1 2 2v11H2V6a2 2 0 0 1 2-2Zm12 4h2a2 2 0 0 1 1.6.8l2 2.7a2 2 0 0 1 .4 1.2V17h-6Zm2 3v3h2.5L18 11Z')+dot(6,19,3)+dot(18,19,3),
 invoice:path('M7 2h10a3 3 0 0 1 3 3v15.5a1.5 1.5 0 0 1-2.3 1.3L15 20l-2.2 1.5a1.5 1.5 0 0 1-1.6 0L9 20l-2.7 1.8A1.5 1.5 0 0 1 4 20.5V5a3 3 0 0 1 3-3Z'+roundRect(7,6,10,3,1.5)+roundRect(7,12,7,3,1.5)),
 ledger:path(roundRect(4,2,17,20,3)+roundRect(10,6,7,2.5,1.25)+roundRect(10,11,7,2.5,1.25)+roundRect(10,16,5,2.5,1.25))+rect(1,5,6,3)+rect(1,11,6,3)+rect(1,17,6,3),
 users:dot(8,7,4)+dot(18,8,3.5)+path('M1 20a7 7 0 0 1 14 0 2 2 0 0 1-2 2H3a2 2 0 0 1-2-2Zm15-6a6 6 0 0 1 7 6 2 2 0 0 1-2 2h-4a4 4 0 0 0 .5-2 9.5 9.5 0 0 0-1.5-6Z'),
 returnArrow:path('M5 12h14a2 2 0 0 1 2 2v5a3 3 0 0 1-3 3H6a3 3 0 0 1-3-3v-5a2 2 0 0 1 2-2Z'+roundRect(8,15,8,3,1.5))+line('M8 3 4 7l4 4M4 7h12a4 4 0 0 1 4 4'),
 project:rect(2,2,3,20)+rect(2,19,20,3)+rect(8,3,10,4,2)+rect(11,9,11,4,2)+rect(15,15,7,4,2),
 badge:path(roundRect(2,5,20,17,4)+disc(12,11,2.5)+'M7 19a5 5 0 0 1 10 0Z')+rect(9,1,6,6,2),
 contract:path('M6 2h9a3 3 0 0 1 3 3v4l-8 8-.6 5H6a3 3 0 0 1-3-3V5a3 3 0 0 1 3-3Z'+roundRect(6,6,9,2.5,1.25)+roundRect(6,11,5,2.5,1.25))+'<g transform="translate(.8 1.5) scale(.88)">'+path('m19 11 2.5 2.5-7.4 7.4-3 .5.5-3Zm1.4-1.4 1-1a1.8 1.8 0 0 1 2.5 2.5l-1 1Z')+'</g>',
 expense:path('M5 2h9a3 3 0 0 1 3 3v6a7.5 7.5 0 0 0-7.5 7.5 7.3 7.3 0 0 0 .8 3.3L8 20l-2.7 1.8A1.5 1.5 0 0 1 3 20.5V4a2 2 0 0 1 2-2Z'+roundRect(6,6,8,2.5,1.25)+roundRect(6,11,4,2.5,1.25))+path(disc(17,18,5)+roundRect(15.8,15,2.4,6,1.2)),
 documents:path('M9 2h5v6a3 3 0 0 0 3 3h5v8a3 3 0 0 1-3 3H9a3 3 0 0 1-3-3V5a3 3 0 0 1 3-3Zm8 .9L21.1 8H17Z'+roundRect(9,14,10,3,1.5))+path('M4 6v12a6 6 0 0 0 1.5 4H5a3 3 0 0 1-3-3V9a3 3 0 0 1 2-3Z'),
 knowledge:path('M7 2h11a3 3 0 0 1 3 3v17H7a5 5 0 0 1-5-5V7a5 5 0 0 1 5-5Zm2 0v11a1 1 0 0 0 1.6.8L13 12l2.4 1.8A1 1 0 0 0 17 13V2ZM7 17a1.5 1.5 0 0 0 0 3h11v-3Z'),
 checklist:path(roundRect(3,4,18,18,3)+roundRect(7,8,3,3,1)+roundRect(12,8,5,3,1)+roundRect(7,14,3,3,1)+roundRect(12,14,5,3,1))+rect(8,1,8,5,2),
 globe:path(disc(12,12,10)+disc(12,12,7))+line('M3 12h18M12 3c-6 4-6 14 0 18M12 3c6 4 6 14 0 18',2.5),
 car:path('M7 3h10a3 3 0 0 1 2.8 2l2 5.7a4 4 0 0 1 .2 1.3v6a2 2 0 0 1-2 2h-1v1a1.5 1.5 0 0 1-3 0v-1H8v1a1.5 1.5 0 0 1-3 0v-1H4a2 2 0 0 1-2-2v-6a4 4 0 0 1 .2-1.3l2-5.7A3 3 0 0 1 7 3Zm.3 3-1.5 4h12.4l-1.5-4ZM5 13v3h4v-3Zm10 0v3h4v-3Z'),
 barcode:rect(2,3,3,18,1.5)+rect(7,3,2,18,1)+rect(11,3,4,18,1.5)+rect(17,3,2,18,1)+rect(21,3,2,18,1),
 folder:path('M5 3h4a3 3 0 0 1 2.4 1.2L13 6h6a3 3 0 0 1 3 3v10a3 3 0 0 1-3 3H5a3 3 0 0 1-3-3V6a3 3 0 0 1 3-3Zm5.5 7v5H8l4 4 4-4h-2.5v-5Z'),
 audit:path(disc(10,10,8)+disc(10,10,5))+line('M16 16l5 5M7.5 10l1.8 1.8 3.2-3.6',2.8),
 matrix:rect(2,2,8.5,8.5,2.5)+rect(13.5,2,8.5,8.5,2.5)+rect(2,13.5,8.5,8.5,2.5)+rect(13.5,13.5,8.5,8.5,2.5),
 tag:path('M6 2h5a4 4 0 0 1 2.8 1.2l7.1 7.1a3 3 0 0 1 0 4.2l-6.4 6.4a3 3 0 0 1-4.2 0l-7.1-7.1A4 4 0 0 1 2 11V6a4 4 0 0 1 4-4Z'+disc(7,7,2)),
 calendar:path(roundRect(2,4,20,18,4)+roundRect(5,8,14,2.5,1.25)+disc(7,15,1.5)+disc(12,15,1.5)+disc(17,15,1.5)+disc(7,19,1)+disc(12,19,1))+rect(5.5,1,3,5)+rect(15.5,1,3,5),
 download:line('M12 3v12m-4-4 4 4 4-4M3 16v3a3 3 0 0 0 3 3h12a3 3 0 0 0 3-3v-3'),
 send:path('m3 8 17-6a1.6 1.6 0 0 1 2 2l-6 17a1.6 1.6 0 0 1-3 .1l-3-7.1 6.6-6.6-8.1 5-5.6-1.4A1.6 1.6 0 0 1 3 8Z'),
 refresh:line('M20 8a8.5 8.5 0 0 0-15-2M4 16a8.5 8.5 0 0 0 15 2M20 3v5h-5M4 21v-5h5'),
 alert:path('M9.4 3.6a3 3 0 0 1 5.2 0l7 12.4a4 4 0 0 1-3.5 6H5.9a4 4 0 0 1-3.5-6Z'+roundRect(10.5,8,3,6,1.5)+disc(12,18,1.5)),
 building:path('M6 2h8a3 3 0 0 1 3 3v4h2a3 3 0 0 1 3 3v10H2V6a4 4 0 0 1 4-4Zm0 4v3h3V6Zm5 0v3h3V6Zm-5 6v3h3v-3Zm5 0v3h3v-3Zm6 1v3h2v-3Zm-7 5v4h4v-4Z'),
 brain:path('M10.5 3.5a3 3 0 0 0-5.7-.8 4 4 0 0 0-2.5 6.6 4.6 4.6 0 0 0 .4 7.4A4.5 4.5 0 0 0 7 22a3.5 3.5 0 0 0 3.5-3.5V14H7a1.5 1.5 0 0 1 0-3h3.5Zm3 0a3 3 0 0 1 5.7-.8 4 4 0 0 1 2.5 6.6 4.6 4.6 0 0 1-.4 7.4A4.5 4.5 0 0 1 17 22a3.5 3.5 0 0 1-3.5-3.5V14H17a1.5 1.5 0 0 0 0-3h-3.5Z'),
 headset:line('M3.5 13v-2a8.5 8.5 0 0 1 17 0v6a4 4 0 0 1-4 4H14')+rect(1,11,6,8,2.5)+rect(17,11,6,8,2.5)+rect(10,19,6,3,1.5),
 sparkles:path('M12 3c1.5 5.5 3.5 7.5 9 9-5.5 1.5-7.5 3.5-9 9-1.5-5.5-3.5-7.5-9-9 5.5-1.5 7.5-3.5 9-9ZM21 1c.5 2 1 2.5 3 3-2 .5-2.5 1-3 3-.5-2-1-2.5-3-3 2-.5 2.5-1 3-3ZM3 18c.5 2 1 2.5 3 3-2 .5-2.5 1-3 3-.5-2-1-2.5-3-3 2-.5 2.5-1 3-3Z'),
 lock:path(roundRect(3,9,18,13,4)+roundRect(10.5,13,3,5,1.5))+line('M7 9V7a5 5 0 0 1 10 0v2'),
 message:path('M6 2h12a4 4 0 0 1 4 4v10a4 4 0 0 1-4 4H9l-4.8 2.7A1.5 1.5 0 0 1 2 21.4V6a4 4 0 0 1 4-4Z'+roundRect(6,7,12,3,1.5)+roundRect(6,13,8,3,1.5)),
 banknote:path(roundRect(2,5,20,14,3)+disc(12,12,3.5)+roundRect(5,10,2,4,1)+roundRect(17,10,2,4,1))+dot(12,12,1.3),
 bag:path('M6 7h12a3 3 0 0 1 3 2.7l1 9A3 3 0 0 1 19 22H5a3 3 0 0 1-3-3.3l1-9A3 3 0 0 1 6 7Zm1 4v2a5 5 0 0 0 10 0v-2h-3v2a2 2 0 0 1-4 0v-2Z')+line('M8 7V6a4 4 0 0 1 8 0v1'),
 pin:path('M12 2a9 9 0 0 1 9 9c0 4.5-5.2 9-7.7 11a2 2 0 0 1-2.6 0C8.2 20 3 15.5 3 11a9 9 0 0 1 9-9Z'+disc(12,10.5,3)),
 factory:path('M17 2h2a2 2 0 0 1 2 1.8l1 16a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2v-9a2 2 0 0 1 3-1.7l3 1.7V9a2 2 0 0 1 3-1.7l4 2.3V4a2 2 0 0 1 2-2ZM5 16v3h3v-3Zm5 0v3h3v-3Zm5 0v3h3v-3Z'),
 bell:path('M12 2a7 7 0 0 1 7 7v2c0 2 1.2 3.5 2.2 5A2 2 0 0 1 19.5 19h-15a2 2 0 0 1-1.7-3c1-1.5 2.2-3 2.2-5V9a7 7 0 0 1 7-7Z')+rect(9,20,6,2.5,1.25),
 gauge:path('M3 20a10 10 0 1 1 18 0 2 2 0 0 1-1.8 1H4.8A2 2 0 0 1 3 20Zm2.7-3H9a3.5 3.5 0 0 1 6 0h3.3a7 7 0 1 0-12.6 0Z')+line('M12 18l4-6',2.8),
 move:line('M7 21V3L3 7m4-4 4 4M17 3v18l-4-4m4 4 4-4'),
 stock:rect(2,2,3,20)+rect(19,2,3,20)+rect(2,10,20,3)+rect(2,19,20,3)+rect(7,3,10,5,1.5)+rect(7,15,4,4,1)+rect(13,15,4,4,1),
 spreadsheet:path(roundRect(2,2,20,20,4)+roundRect(5,6,14,3,1)+roundRect(5,12,5,3,1)+roundRect(13,12,6,3,1)+roundRect(5,18,5,2,1)+roundRect(13,18,6,2,1)),
 gears:cog(8,8,7)+cog(17,17,6),
 cloud:path('M8 5a6 6 0 0 1 11 3 5 5 0 0 1 0 10h-4v-3h2l-5-5-5 5h2v3H6A5 5 0 0 1 5.5 8 6 6 0 0 1 8 5Z')+line('M12 15v7m-3-3 3 3 3-3'),
 user:path(disc(12,12,10)+disc(12,8,3)+'M5.7 18a7.5 7.5 0 0 1 12.6 0 8 8 0 0 1-12.6 0Z'),
 catalog:path('M2 5a2 2 0 0 1 1.7-2c3-.4 5.3.2 6.8 1.3V22C8.3 20.7 6 20.4 3 21a1 1 0 0 1-1-1Zm19-2a2 2 0 0 1 1 2v15a1 1 0 0 1-1 1c-3-.6-5.3-.3-7.5 1V4.3C15 3.2 17.3 2.6 21 3Z'+roundRect(5,8,3,3,1)+roundRect(5,14,3,3,1)+roundRect(16,8,3,3,1)+roundRect(16,14,3,3,1)),
 search:path(disc(10,10,8)+disc(10,10,4.8))+line('M16 16l5 5',3.5),
 gear:cog(9,9,8)+cog(18,18,5),
 scanner:line('M7 3H4a1 1 0 0 0-1 1v3m14-4h3a1 1 0 0 1 1 1v3M3 17v3a1 1 0 0 0 1 1h3m14-4v3a1 1 0 0 1-1 1h-3',2.8)+rect(7,7,2.5,10,1)+rect(11,7,2,10,1)+rect(14.5,7,2.5,10,1),
 sliders:path(roundRect(2,2,20,20,4)+'M6 7h6.4a3 3 0 0 1 5.2 0h.4a1.5 1.5 0 0 1 0 3h-.4a3 3 0 0 1-5.2 0H6a1.5 1.5 0 0 1 0-3ZM6 15h.4a3 3 0 0 1 5.2 0H18a1.5 1.5 0 0 1 0 3h-6.4a3 3 0 0 1-5.2 0H6a1.5 1.5 0 0 1 0-3Z'),
 star:'<path d="m12 3 2.8 5.7 6.2.9-4.5 4.4 1.1 6.2-5.6-3-5.6 3 1.1-6.2L3 9.6l6.2-.9Z" stroke="currentColor" stroke-width="2.5" stroke-linejoin="round"/>',
 menu:dot(5,5,2)+dot(12,5,2)+dot(19,5,2)+dot(5,12,2)+dot(12,12,2)+dot(19,12,2)+dot(5,19,2)+dot(12,19,2)+dot(19,19,2),
 more:dot(4,12,2.2)+dot(12,12,2.2)+dot(20,12,2.2)
};
artwork.robot=artwork.cocoBot;
artwork.apps=artwork.matrix;

/** SVG contents shared by the existing compact and complete renderers. */
export const icons=Object.fromEntries(Object.entries(artwork).map(([name,body])=>[name,
 '<g class="cocoIconPrimary" color="var(--coco-glyph-color, var(--gama-blue, #263238))" fill="'+(name==='star'?'none':'currentColor')+'" stroke="none">'+body+'</g>'
]));

/** Complete SVG for module, metric and navigation artwork. */
export function moduleIcon(name) {
 return icons[name]?'<svg class="arcIco arcHomeIllustration arcModuleGlyph" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" aria-hidden="true" focusable="false">'+icons[name]+'</svg>':'';
}
