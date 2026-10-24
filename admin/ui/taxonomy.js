// Lookups over /api/taxonomy, including the app's image rule: a category shows its own illustration, else its
// subgroup's, else its group's.
export function taxonomyIndex({ groups, subgroups, categories, pending = [] }) {
  const group = new Map(groups.map((g) => [g.id, g]));
  const subgroup = new Map(subgroups.map((s) => [s.id, s]));
  const category = new Map(categories.map((c) => [c.id, c]));
  const pendingKeys = new Set(pending.map((a) => `${a.level}:${a.node_id}`));

  /** The node whose illustration a record in this category shows, with its URL, or null. */
  function imageFor(categoryId) {
    const c = category.get(categoryId);
    if (!c) return null;
    const s = subgroup.get(c.subgroup_id);
    const g = s && group.get(s.group_id);
    for (const [level, node] of [['category', c], ['subgroup', s], ['group', g]])
      if (node?.image_url) return { level, node, url: node.image_url };
    return null;
  }

  /** For a node without its own illustration, the ancestor whose illustration it shows. */
  function inherited(level, id) {
    if (level === 'group') return null;
    if (level === 'subgroup') {
      const g = group.get(subgroup.get(id)?.group_id);
      return g?.image_url ? { level: 'group', node: g, url: g.image_url } : null;
    }
    const found = imageFor(id);
    return found && found.level !== 'category' ? found : null;
  }

  return {
    group,
    subgroup,
    category,
    imageFor,
    inherited,
    hasPending: (level, id) => pendingKeys.has(`${level}:${id}`),
    path: (categoryId) => category.get(categoryId)?.path || categoryId,
  };
}
