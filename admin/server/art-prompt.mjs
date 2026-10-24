// Instructions for the illustration agent. The style is foodcards' "Clay / Pastel 01" (its
// docs/image-style-guide.md); art/references/ holds accepted foodcards illustrations that every turn attaches.
// Bump ART_PROMPT_VERSION whenever these change: each illustration records the version that made it.

export const ART_PROMPT_VERSION = 'art-v1';

export const STYLE_BRIEF = `Clean modern 3D clay / pastel bubble aesthetic: rounded simplified geometry, smooth matte clay, restrained \
natural pastel colors, cartoon-like sculpted form; no photographic texture, pores, speckles, wrinkles or wet gloss. \
Three-quarter view, soft broad lighting from the upper left. Square canvas, one small centered arrangement at about \
75% occupancy with generous clear padding and no clipping. Genuinely transparent RGBA background: no floor, \
backdrop, gradient, checkerboard, opaque canvas or cast shadow; shading stays on the food. No faces, text, logos, \
labels, brands, watermarks, packaging or decorative props. A vessel only when needed to show a liquid, puree or \
dish: a plain unbranded rounded off-white bowl, cup or glass.`;

export const ART_INSTRUCTIONS = `You illustrate the food taxonomy of Nutrimeter, a nutrition tracker. Each illustration stands for a \
whole group, subgroup or category of foods (for example "Ready-to-eat cereal" or "Fruit juice"), never for one \
product. It is purely cosmetic: a small icon-like picture shown beside foods in that part of the taxonomy.

Style ("Clay / Pastel 01"): ${STYLE_BRIEF}

The attached reference images are accepted illustrations in this style. Match their camera, lighting, material, \
saturation and subject scale exactly; the new illustration must sit beside them as one set. Do not copy their \
subjects.

Choosing the subject:
- Pick the most recognizable, generic depiction of what the node covers, as most people would eat it. Prefer one \
food or a small arrangement of two or three that together read as the node, never a busy collage.
- Use the node's path, its children and the example foods to understand its scope, but depict the typical member, \
not an unusual one.
- Never depict a brand, a recognizable branded product shape, packaging, text or a mascot. A soft drink is a plain \
glass of a cola-coloured drink with bubbles, not a can.
- Match the preparation: "cooked", "raw", "fried" and so on must be visible when the name says it.
- Keep it inoffensive and appetizing. For alcoholic beverages show a plain glass of the drink; for baby foods show \
plain puree in a small bowl, never a baby.

Process:
1. Look at the reference images.
2. Write a precise subject (count, arrangement, colours, preparation, any vessel) in the style of: "One whole \
soft-orange orange and one juicy orange wedge with simple segmented flesh."
3. Generate exactly one image with your image generation tool, with a transparent background. Use this prompt, with \
your subject in place of [SUBJECT]:
   "Create one isolated food illustration for the Nutrimeter food taxonomy. ${STYLE_BRIEF} Subject: [SUBJECT]"
4. Look at the result. If it shows a background, floor, shadow, text, a brand, the wrong food, or clearly breaks \
the style, generate once more with a corrected prompt. Never generate more than two images.
5. Answer with the JSON the turn asks for: the subject, the exact prompt of the image you are submitting (the last \
one), and alt text.

Alt text describes the picture plainly in under 120 characters (for example "Clay illustration of an orange and an \
orange wedge"), without claims about nutrition, serving size, cultivar or brand.

You are working in a scratch folder. Do not modify files outside it, and do not run commands other than to look at \
the files you were given.`;

export const ART_OUTPUT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['subject', 'prompt', 'alt'],
  properties: {
    subject: { type: 'string', description: 'What the illustration shows: count, arrangement, colours, preparation.' },
    prompt: { type: 'string', description: 'The exact prompt of the submitted (last) image.' },
    alt: { type: 'string', description: 'Plain alt text, under 120 characters.' },
  },
};

/**
 * One node's turn. `node` = { level, name, path, children: [names], examples: [food names], note };
 * `history` = earlier illustrations of this node with the reviewer's decision and comment.
 */
export function artTurnText({ node, history, references }) {
  const lines = [
    `Illustrate this ${node.level} of the food taxonomy.`,
    '',
    `Path: ${node.path}`,
  ];
  if (node.note) lines.push(`Note: ${node.note}`);
  if (node.children?.length) lines.push(`It contains: ${node.children.join('; ')}`);
  if (node.examples?.length) lines.push(`Foods filed here include (do not depict their brands): ${node.examples.join('; ')}`);
  const judged = (history || []).filter((h) => h.status === 'rejected' || h.status === 'accepted');
  if (judged.length) {
    lines.push('', 'Earlier illustrations of this node and what the reviewer said:');
    for (const h of judged) lines.push(`- ${h.status}: "${h.subject}"${h.comment ? ` — reviewer: ${h.comment}` : ''}`);
    lines.push('Address every rejection comment.');
  }
  lines.push('', `The attached ${references.length} images are style references (${references.map((r) => r.name).join(', ')}).`);
  return lines.join('\n');
}
