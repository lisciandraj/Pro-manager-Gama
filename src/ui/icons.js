/* Coco ERP — one icon family for tiles, navigation and business views.
   Reference: IMG_1313, 19 October 2026. A clear blue contour, one orange detail,
   a transparent 24px canvas. Each colour is an authored part of the drawing. */
const artwork={
 home:[
  '<path d="m3 10 9-7 9 7M5 9v12h14V9"/>',
  '<path d="M10 21v-7h4v7"/>'
 ],
 chart:[
  '<path d="M10 3a9 9 0 1 0 11 11H10Z"/>',
  '<path d="M14 2v8h8a9 9 0 0 0-8-8Z"/>'
 ],
 sales:[
  '<rect x="3" y="16" width="4" height="5" rx=".5"/><rect x="10" y="12" width="4" height="9" rx=".5"/><rect x="17" y="8" width="4" height="13" rx=".5"/>',
  '<path d="m3 11 6-6 3 2 7-5M15 2h4v4"/>'
 ],
 cocoBot:[
  '<path d="M7 7.5h10a4.5 4.5 0 0 1 4.5 4.5v6a4.5 4.5 0 0 1-4.5 4.5H7A4.5 4.5 0 0 1 2.5 18v-6A4.5 4.5 0 0 1 7 7.5Zm1 2.7A2.8 2.8 0 0 0 5.2 13v4A2.8 2.8 0 0 0 8 19.8h8a2.8 2.8 0 0 0 2.8-2.8v-4a2.8 2.8 0 0 0-2.8-2.8Z" fill="currentColor" fill-rule="evenodd" stroke="none"/><rect x=".8" y="12" width="2.5" height="6.5" rx="1.1" fill="currentColor" stroke="none"/><rect x="20.7" y="12" width="2.5" height="6.5" rx="1.1" fill="currentColor" stroke="none"/><rect x="7.5" y="12.7" width="2.8" height="4.3" rx="1" fill="currentColor" stroke="none"/><rect x="13.7" y="12.7" width="2.8" height="4.3" rx="1" fill="currentColor" stroke="none"/>',
  '<path d="M11.5 7.5V5.3c0-1.6.8-2.7 2.2-2.9" stroke-linecap="round"/><circle cx="14.2" cy="2.4" r="1.6" fill="currentColor" stroke="none"/>'
 ],
 handshake:[
  '<path d="m3 8 4-4 5 2 4-2 5 4-4 10-4 3-7-6Zm9-2-4 4 2 2 3-3 5 5M7 17l3 3M15 16l2 2"/>',
  '<path d="m1 9 3-2 3 7-3 2Z"/>'
 ],
 cube:[
  '<path d="m12 5 6 3.5v7L12 19l-6-3.5v-7ZM6 8.5l6 3.5 6-3.5M12 12v7"/>',
  '<path d="M7 2H2v5M17 2h5v5M2 17v5h5M22 17v5h-5"/>'
 ],
 cart:[
  '<path d="M2 4h3l3 12h10l3-9H6"/><circle cx="9" cy="20" r="1.5"/><circle cx="18" cy="20" r="1.5"/>',
  '<path d="M14 3v8m-3-3 3 3 3-3"/>'
 ],
 warehouse:[
  '<path d="m3 10 9-6 9 6v11H3ZM7 21v-7h10v7M7 17h10"/>',
  '<path d="M12 4V1h5l-1 2h-4"/>'
 ],
 truck:[
  '<path d="M2 5h12v12H2ZM14 9h4l4 5v3h-8M18 9v5h4"/><circle cx="6" cy="19" r="2"/><circle cx="18" cy="19" r="2"/>',
  '<path d="M5 9h6M5 12h4"/>'
 ],
 invoice:[
  '<path d="M5 2h14v11M5 2v19l3-2 3 2 2-1M8 6h8M8 10h6"/>',
  '<path d="m14 18 3 3 5-7"/>'
 ],
 ledger:[
  '<path d="M6 3h14v18H6ZM3 7h3M3 12h3M3 17h3M10 11h6M10 16h4"/>',
  '<path d="M12 3v5l2-1 2 1V3"/>'
 ],
 users:[
  '<rect x="4" y="3" width="6" height="8" rx="3"/><rect x="14" y="3" width="6" height="8" rx="3"/><path d="M2 20v-3a6 6 0 0 1 7-6M22 20v-3a6 6 0 0 0-7-6"/>',
  '<path d="M8 16h9l-2-2M16 20H7l2 2"/>'
 ],
 returnArrow:[
  '<path d="M5 9v11h14V9M8 11h8v5H8Z"/>',
  '<path d="M19 6H5m4-4L5 6l4 4"/>'
 ],
 project:[
  '<path d="M3 3v18h18M7 5h7v3H7ZM10 11h10v3H10Z"/>',
  '<path d="M15 17h6v3h-6Z"/>'
 ],
 badge:[
  '<rect x="3" y="6" width="18" height="15" rx="2"/><circle cx="12" cy="12" r="2"/><path d="M8 18a4 4 0 0 1 8 0"/>',
  '<rect x="9" y="2" width="6" height="5" rx="1"/>'
 ],
 documents:[
  '<path d="M7 2h8l6 6v14H7ZM3 6v14M11 13h6M11 17h4"/>',
  '<path d="M15 2v6h6"/>'
 ],
 knowledge:[
  '<path d="M5 3h14v18H6a3 3 0 0 1-3-3V5a2 2 0 0 1 2-2ZM3 17h16"/>',
  '<path d="M9 3v9l3-2 3 2V3"/>'
 ],
 checklist:[
  '<path d="M8 4H4v18h16V4h-4M8 2h8v4H8ZM12 11h5M12 17h5"/>',
  '<path d="m6 11 1 1 2-3m-3 8 1 1 2-3"/>'
 ],
 globe:[
  '<circle cx="12" cy="12" r="9"/><ellipse cx="12" cy="12" rx="4" ry="9"/><path d="M3 12h18"/>',
  '<path d="M5 6h14"/>'
 ],
 car:[
  '<path d="m4 11 3-7h10l3 7M3 11h18v7H3ZM5 18v3M19 18v3M6 14h2M16 14h2"/>',
  '<path d="M9 4V2h6v2M10 17h4"/>'
 ],
 barcode:[
  '<path d="M3 5v14M6 5v14M9 5v14M16 5v14M21 5v14"/>',
  '<path d="M13 5v14" stroke-width="3"/>'
 ],
 folder:[
  '<path d="M3 20V5h7l3 3h8v12h-5M3 20h4"/>',
  '<path d="M12 13v9m-3-3 3 3 3-3M16 11h2"/>'
 ],
 audit:[
  '<path d="m17 17 5 5"/><circle cx="10" cy="10" r="7"/>',
  '<path d="m7 10 2 2 4-4"/>'
 ],
 matrix:[
  '<rect x="3" y="3" width="6" height="6" rx=".5"/><rect x="15" y="3" width="6" height="6" rx=".5"/><rect x="3" y="15" width="6" height="6" rx=".5"/>',
  '<rect x="15" y="15" width="6" height="6" rx=".5"/>'
 ],
 tag:[
  '<path d="M3 3h8l11 11-8 8L3 11Z"/><circle cx="7" cy="7" r="1"/>',
  '<path d="m11 15 4-4"/>'
 ],
 calendar:[
  '<rect x="3" y="5" width="18" height="16" rx="1"/><path d="M7 3v4M17 3v4M3 10h18"/>',
  '<path d="M7 14h1M12 14h1M17 14h1M7 18h1M12 18h1"/>'
 ],
 download:[
  '<path d="M3 15v6h18v-6"/>',
  '<path d="M12 3v13m-4-4 4 4 4-4"/>'
 ],
 send:[
  '<path d="m21 3-7 18-4-8-8-4Z"/>',
  '<path d="m10 13 7-7"/>'
 ],
 refresh:[
  '<path d="M4 8a8 8 0 0 1 14-3M20 16a8 8 0 0 1-14 3"/>',
  '<path d="M18 2v4h-4M6 22v-4h4"/>'
 ],
 alert:[
  '<path d="m12 3 10 18H2Z"/>',
  '<path d="M12 9v5"/><circle cx="12" cy="17.5" r="1" fill="currentColor" stroke="none"/>'
 ],
 building:[
  '<path d="M3 21V3h11v18M14 10h7v11M1 21h22M7 7h3M7 11h3M7 15h3M17 14h1M17 18h1"/>',
  '<path d="M8 21v-3h2v3"/>'
 ],
 brain:[
  '<path d="M12 5a3 3 0 0 0-6-1 4 4 0 0 0-3 6 4 4 0 0 0 1 8 4 4 0 0 0 8 0V5Zm0 0a3 3 0 0 1 6-1 4 4 0 0 1 3 6 4 4 0 0 1-1 8 4 4 0 0 1-8 0M6 4l1 3M3 10l4 1M18 4l-1 3M21 10l-4 1"/>',
  '<path d="M8 15h8M12 12v6"/>'
 ],
 headset:[
  '<path d="M4 12V10a8 8 0 0 1 16 0v7M4 12H2v7h4v-7ZM20 12h2v7h-4v-7Z"/>',
  '<path d="M20 19a3 3 0 0 1-3 3h-5"/>'
 ],
 sparkles:[
  '<path d="m12 4 2.5 5.5L20 12l-5.5 2.5L12 20l-2.5-5.5L4 12l5.5-2.5Z"/>',
  '<path d="M21 2v4M19 4h4M3 18v4M1 20h4"/>'
 ],
 lock:[
  '<rect x="5" y="10" width="14" height="12" rx="1"/><path d="M8 10V6a4 4 0 0 1 8 0v4"/>',
  '<path d="M12 15v3"/>'
 ],
 message:[
  '<path d="M21 15a2 2 0 0 1-2 2H9l-6 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2Z"/><path d="M7 8h10"/>',
  '<path d="M7 12h6"/>'
 ],
 banknote:[
  '<path d="M3 8a9 9 0 0 1 16-3M21 16a9 9 0 0 1-16 3M19 2v4h-4M5 22v-4h4"/>',
  '<path d="M15 8h-5a2 2 0 0 0 0 4h4a2 2 0 0 1 0 4H9M12 6v12"/>'
 ],
 bag:[
  '<path d="M5 7h14l2 14H3ZM8 7V5a4 4 0 0 1 8 0v2"/>',
  '<path d="M8 14h8m-3-3 3 3-3 3"/>'
 ],
 pin:[
  '<path d="M19 9c0 5-7 12-7 12S5 14 5 9a7 7 0 0 1 14 0Z"/>',
  '<circle cx="12" cy="9" r="2" fill="currentColor" stroke="none"/>'
 ],
 factory:[
  '<path d="M3 21V10l6 3V9l6 3V3h4l2 18ZM6 17h1M11 17h1M16 17h1"/>',
  '<path d="M16 3V1h2"/>'
 ],
 bell:[
  '<path d="M18 9a6 6 0 0 0-12 0c0 6-3 6-3 9h18c0-3-3-3-3-9Z"/>',
  '<path d="M10 21h4M12 3V1"/>'
 ],
 gauge:[
  '<path d="M4 19a9 9 0 1 1 16 0ZM5 9l2 1M12 5v2M19 9l-2 1"/>',
  '<path d="m12 15 4-5"/><circle cx="12" cy="15" r="1.5" fill="currentColor" stroke="none"/>'
 ],
 move:[
  '<path d="M7 3v17M3 7l4-4 4 4"/>',
  '<path d="M17 21V4m-4 13 4 4 4-4"/>'
 ],
 stock:[
  '<path d="M3 3v18M21 3v18M3 11h18M3 21h18M6 5h5v6M14 6h4v5"/>',
  '<path d="M7 21v-7h10v7M12 14v3"/>'
 ],
 spreadsheet:[
  '<rect x="3" y="3" width="18" height="18" rx="1"/><path d="M3 9h18M3 15h18M9 9v12"/>',
  '<path d="M15 9v12"/>'
 ],
 gears:[
  '<path d="M10 3H6L5 6 2 7v4l3 1 1 3h4l1-3 3-1V7l-3-1ZM8 7a2 2 0 1 0 0 4 2 2 0 0 0 0-4Z"/>',
  '<path d="M19 13h-4l-1 2-2 1v3l2 1 1 2h4l1-2 2-1v-3l-2-1Z"/><circle cx="17" cy="17.5" r="1.5"/>'
 ],
 cloud:[
  '<path d="M7 18H6a4 4 0 0 1-.5-8 6.5 6.5 0 0 1 12-1A4.5 4.5 0 0 1 19 18h-2"/>',
  '<path d="M12 12v10m-3-3 3 3 3-3"/>'
 ],
 user:[
  '<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M7 18a5 5 0 0 1 10 0"/>',
  '<circle cx="12" cy="9" r="3"/>'
 ],
 catalog:[
  '<path d="M12 5C9 3 5 3 2 4v16c3-1 7-1 10 1 3-2 7-2 10-1V4c-3-1-7-1-10 1ZM12 5v16M5 9h4M15 9h4"/>',
  '<path d="M5 13h4M15 13h4"/>'
 ],
 search:[
  '<circle cx="10" cy="10" r="7"/>',
  '<path d="m16 16 6 6"/>'
 ],
 gear:[
  '<path d="M13.80 7.45L13.92 8.03L15.45 8.10L15.45 9.90L13.92 9.97L13.80 10.55L13.61 11.12L14.90 11.94L14.00 13.50L12.64 12.80L12.24 13.24L11.80 13.64L12.50 15.00L10.94 15.90L10.12 14.61L9.55 14.80L8.97 14.92L8.90 16.45L7.10 16.45L7.03 14.92L6.45 14.80L5.88 14.61L5.06 15.90L3.50 15.00L4.20 13.64L3.76 13.24L3.36 12.80L2.00 13.50L1.10 11.94L2.39 11.12L2.20 10.55L2.08 9.97L0.55 9.90L0.55 8.10L2.08 8.03L2.20 7.45L2.39 6.88L1.10 6.06L2.00 4.50L3.36 5.20L3.76 4.76L4.20 4.36L3.50 3.00L5.06 2.10L5.88 3.39L6.45 3.20L7.03 3.08L7.10 1.55L8.90 1.55L8.97 3.08L9.55 3.20L10.12 3.39L10.94 2.10L12.50 3.00L11.80 4.36L12.24 4.76L12.64 5.20L14.00 4.50L14.90 6.06L13.61 6.88ZM4.75 9a3.25 3.25 0 1 0 6.5 0a3.25 3.25 0 1 0 -6.5 0Z" fill="currentColor" fill-rule="evenodd" stroke="none"/><path d="M22.32 17.15L22.39 17.67L23.50 17.87L23.31 19.44L22.18 19.36L21.99 19.85L21.74 20.31L22.53 21.12L21.45 22.28L20.58 21.56L20.14 21.84L19.67 22.07L19.83 23.19L18.27 23.49L18.00 22.40L17.47 22.37L16.96 22.27L16.43 23.27L14.99 22.60L15.41 21.56L15.01 21.22L14.64 20.84L13.63 21.34L12.86 19.96L13.81 19.36L13.68 18.85L13.61 18.33L12.50 18.13L12.69 16.56L13.82 16.64L14.01 16.15L14.26 15.69L13.47 14.88L14.55 13.72L15.42 14.44L15.86 14.16L16.33 13.93L16.17 12.81L17.73 12.51L18.00 13.60L18.53 13.63L19.04 13.73L19.57 12.73L21.01 13.40L20.59 14.44L20.99 14.78L21.36 15.16L22.37 14.66L23.14 16.04L22.19 16.64ZM15.8 18a2.2 2.2 0 1 0 4.4 0a2.2 2.2 0 1 0 -4.4 0Z" fill="currentColor" fill-rule="evenodd" stroke="none"/>',
  '<circle cx="8" cy="9" r="4.35" stroke-width=".7"/><circle cx="18" cy="18" r="3.1" stroke-width=".65"/>'
 ],
 scanner:[
  '<path d="M7 3H3v4M17 3h4v4M3 17v4h4M21 17v4h-4M7 8v8M10 8v8M14 8v8M17 8v8"/>',
  '<path d="M1 12h22"/>'
 ],
 sliders:[
  '<path d="M3 6h8M15 6h6M3 12h3M10 12h11M3 18h11M18 18h3"/>',
  '<circle cx="13" cy="6" r="2"/><circle cx="8" cy="12" r="2"/><circle cx="16" cy="18" r="2"/>'
 ],
 star:[
  '<path d="m12 3 2.8 5.7 6.2.9-4.5 4.4 1.1 6.2-5.6-3-5.6 3 1.1-6.2L3 9.6l6.2-.9Z"/>',
  '<path d="m12 10 2 2-2 2-2-2Z" fill="currentColor" stroke="none"/>'
 ],
 menu:[
  '<path d="M3 5h18M3 19h18"/>',
  '<path d="M3 12h18"/>'
 ],
 more:[
  '<circle cx="4" cy="12" r="1.5"/><circle cx="20" cy="12" r="1.5"/>',
  '<circle cx="12" cy="12" r="1.5"/>'
 ]
};
artwork.robot=artwork.cocoBot;
artwork.apps=artwork.matrix;

const layer=(body,role)=>'<g class="cocoIcon'+(role==='blue'?'Primary':'Accent')+'" color="var(--gama-'+role+', '+(role==='blue'?'#157F98':'#F87826')+')" stroke="var(--gama-'+role+', '+(role==='blue'?'#157F98':'#F87826')+')" fill="none" stroke-width="2" stroke-linecap="square" stroke-linejoin="round">'+body+'</g>';
/** SVG contents for existing compact renderers, with the same two layers. */
export const icons=Object.fromEntries(Object.entries(artwork).map(([name,[primary,accent]])=>[name,layer(primary,'blue')+layer(accent,'orange')]));

/** Complete SVG for module, metric and navigation artwork. */
export function moduleIcon(name) {
 return icons[name]?'<svg class="arcIco arcHomeIllustration arcModuleGlyph" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" aria-hidden="true" focusable="false">'+icons[name]+'</svg>':'';
}
