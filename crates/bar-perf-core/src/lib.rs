use std::sync::atomic::{AtomicUsize, Ordering};

/// Contiguous unit representation for Data-Oriented Design (DOD).
/// Packed and fixed at exactly 40 bytes per unit across C, Rust, and LuaJIT FFI.
#[repr(C)]
#[derive(Clone, Copy, Default, Debug)]
pub struct UnitStatePacked {
    pub id: u32,
    pub x: f32,
    pub y: f32,
    pub z: f32,
    pub vx: f32,
    pub vz: f32,
    pub hp: f32,
    pub max_hp: f32,
    pub team_id: u16,
    pub def_id: u16,
    pub flags: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Default, Debug)]
pub struct ProjectileInput {
    pub id: u32,
    pub x: f32,
    pub y: f32,
    pub z: f32,
    pub radius: f32,
    pub damage: f32,
    pub team_id: u16,
    pub weapon_def_id: u16,
}

#[repr(C)]
#[derive(Clone, Copy, Default, Debug)]
pub struct BatchHitResult {
    pub projectile_id: u32,
    pub target_unit_id: u32,
    pub damage: f32,
    pub hit_distance: f32,
}

/// High-Performance Spatial Grid & Batch Unit Manager
pub struct BatchUnitManager {
    pub units: Vec<UnitStatePacked>,
    pub cell_size: f32,
    pub inv_cell_size: f32,
    pub width_cells: usize,
    pub height_cells: usize,
    pub grid_cells: Vec<Vec<u32>>,
}

impl BatchUnitManager {
    pub fn new(map_width: f32, map_height: f32, cell_size: f32) -> Self {
        let cs = if cell_size <= 0.0 { 128.0 } else { cell_size };
        let w = ((map_width / cs).ceil() as usize).max(1);
        let h = ((map_height / cs).ceil() as usize).max(1);
        let total = w * h;

        Self {
            units: Vec::with_capacity(8192),
            cell_size: cs,
            inv_cell_size: 1.0 / cs,
            width_cells: w,
            height_cells: h,
            grid_cells: vec![Vec::with_capacity(32); total],
        }
    }

    #[inline(always)]
    fn cell_index(&self, x: f32, z: f32) -> Option<usize> {
        if x < 0.0 || z < 0.0 {
            return None;
        }
        let cx = (x * self.inv_cell_size) as usize;
        let cz = (z * self.inv_cell_size) as usize;
        if cx < self.width_cells && cz < self.height_cells {
            Some(cz * self.width_cells + cx)
        } else {
            None
        }
    }

    /// Update ALL units in ONE single batch memory copy / assignment.
    /// Eliminates thousands of individual Lua -> C++ stack calls.
    pub fn update_batch(&mut self, data: &[UnitStatePacked]) {
        self.units.clear();
        self.units.extend_from_slice(data);

        // Clear spatial cells
        for cell in &mut self.grid_cells {
            cell.clear();
        }

        // Rebuild spatial grid in single linear sweep (cache friendly)
        for (idx, u) in self.units.iter().enumerate() {
            if (u.flags & 1) != 0 || u.hp > 0.0 {
                if let Some(c_idx) = self.cell_index(u.x, u.z) {
                    self.grid_cells[c_idx].push(idx as u32);
                }
            }
        }
    }

    /// Query nearby units in radius with optional team filter.
    /// team_filter: -1 for all, >= 0 for specific team, -2 for enemies only (needs enemy check)
    pub fn query_radius(&self, x: f32, z: f32, radius: f32, team_filter: i32, out: &mut [u32]) -> usize {
        let r2 = radius * radius;
        let min_x = (x - radius).max(0.0);
        let max_x = x + radius;
        let min_z = (z - radius).max(0.0);
        let max_z = z + radius;

        let start_cx = (min_x * self.inv_cell_size) as usize;
        let end_cx = ((max_x * self.inv_cell_size) as usize).min(self.width_cells - 1);
        let start_cz = (min_z * self.inv_cell_size) as usize;
        let end_cz = ((max_z * self.inv_cell_size) as usize).min(self.height_cells - 1);

        let mut count = 0;
        let max_len = out.len();

        for cz in start_cz..=end_cz {
            let row_offset = cz * self.width_cells;
            for cx in start_cx..=end_cx {
                let cell_idx = row_offset + cx;
                for &unit_idx in &self.grid_cells[cell_idx] {
                    let u = &self.units[unit_idx as usize];
                    if team_filter >= 0 && u.team_id as i32 != team_filter {
                        continue;
                    }
                    let dx = u.x - x;
                    let dz = u.z - z;
                    if dx * dx + dz * dz <= r2 {
                        if count < max_len {
                            out[count] = u.id;
                            count += 1;
                        } else {
                            return count;
                        }
                    }
                }
            }
        }
        count
    }

    /// High-Speed Batch Collision Detection:
    /// Checks an entire array of projectiles against all active units in one SIMD-ready pass.
    pub fn batch_projectile_collisions(
        &self,
        projectiles: &[ProjectileInput],
        out_hits: &mut [BatchHitResult],
    ) -> usize {
        let mut hit_count = 0;
        let max_hits = out_hits.len();

        for p in projectiles {
            if hit_count >= max_hits {
                break;
            }
            if self.cell_index(p.x, p.z).is_some() {
                // Check current cell and adjacent 8 cells
                let cx = (p.x * self.inv_cell_size) as usize;
                let cz = (p.z * self.inv_cell_size) as usize;

                let start_cx = cx.saturating_sub(1);
                let end_cx = (cx + 1).min(self.width_cells - 1);
                let start_cz = cz.saturating_sub(1);
                let end_cz = (cz + 1).min(self.height_cells - 1);

                for adj_z in start_cz..=end_cz {
                    let row = adj_z * self.width_cells;
                    for adj_x in start_cx..=end_cx {
                        for &u_idx in &self.grid_cells[row + adj_x] {
                            let u = &self.units[u_idx as usize];
                            // No friendly fire on same team
                            if u.team_id == p.team_id {
                                continue;
                            }
                            let dx = u.x - p.x;
                            let dz = u.z - p.z;
                            let dist2 = dx * dx + dz * dz;
                            let hit_r = p.radius + 16.0; // unit average radius
                            if dist2 <= hit_r * hit_r && hit_count < max_hits {
                                out_hits[hit_count] = BatchHitResult {
                                    projectile_id: p.id,
                                    target_unit_id: u.id,
                                    damage: p.damage,
                                    hit_distance: dist2.sqrt(),
                                };
                                hit_count += 1;
                            }
                        }
                    }
                }
            }
        }
        hit_count
    }
}

// ---------------------------------------------------------------------------
// C-ABI Exports for LuaJIT FFI (Zero-Cost Interop)
// ---------------------------------------------------------------------------

static INSTANCES: AtomicUsize = AtomicUsize::new(0);

#[no_mangle]
pub extern "C" fn bar_perf_core_version() -> u32 {
    102 // v1.0.2 (Batch Memory & DOD Architecture)
}

#[no_mangle]
pub extern "C" fn bar_batch_manager_create(map_w: f32, map_h: f32, cell_size: f32) -> *mut BatchUnitManager {
    INSTANCES.fetch_add(1, Ordering::Relaxed);
    Box::into_raw(Box::new(BatchUnitManager::new(map_w, map_h, cell_size)))
}

/// Deallocate the batch unit manager.
///
/// # Safety
/// Caller must ensure `mgr` is a valid pointer returned by `bar_batch_manager_create`.
#[no_mangle]
pub unsafe extern "C" fn bar_batch_manager_destroy(mgr: *mut BatchUnitManager) {
    if !mgr.is_null() {
        INSTANCES.fetch_sub(1, Ordering::Relaxed);
        drop(Box::from_raw(mgr));
    }
}

/// Bulk update 5,000+ units in ONE single call via memory pointer.
///
/// # Safety
/// Caller must guarantee `mgr` is a valid pointer and `states` points to an array of at least `count` elements.
#[no_mangle]
pub unsafe extern "C" fn bar_batch_update_units(
    mgr: *mut BatchUnitManager,
    states: *const UnitStatePacked,
    count: usize,
) {
    if mgr.is_null() || states.is_null() || count == 0 {
        return;
    }
    let m = &mut *mgr;
    let slice = std::slice::from_raw_parts(states, count);
    m.update_batch(slice);
}

/// Query nearby units in radius with optional team filter.
///
/// # Safety
/// Caller must guarantee `mgr` is valid and `out_ids` points to writable memory of at least `out_capacity` u32s.
#[no_mangle]
pub unsafe extern "C" fn bar_batch_query_radius(
    mgr: *const BatchUnitManager,
    x: f32,
    z: f32,
    radius: f32,
    team_filter: i32,
    out_ids: *mut u32,
    out_capacity: usize,
) -> usize {
    if mgr.is_null() || out_ids.is_null() || out_capacity == 0 {
        return 0;
    }
    let m = &*mgr;
    let slice = std::slice::from_raw_parts_mut(out_ids, out_capacity);
    m.query_radius(x, z, radius, team_filter, slice)
}

/// High-Speed Batch Collision Detection
///
/// # Safety
/// Caller must guarantee valid pointers and slices according to counts.
#[no_mangle]
pub unsafe extern "C" fn bar_batch_check_projectile_hits(
    mgr: *const BatchUnitManager,
    projectiles: *const ProjectileInput,
    proj_count: usize,
    out_hits: *mut BatchHitResult,
    max_hits: usize,
) -> usize {
    if mgr.is_null() || projectiles.is_null() || out_hits.is_null() || proj_count == 0 || max_hits == 0 {
        return 0;
    }
    let m = &*mgr;
    let projs = std::slice::from_raw_parts(projectiles, proj_count);
    let hits = std::slice::from_raw_parts_mut(out_hits, max_hits);
    m.batch_projectile_collisions(projs, hits)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_unit_state_packed_size_and_alignment() {
        assert_eq!(std::mem::size_of::<UnitStatePacked>(), 40);
        assert_eq!(std::mem::align_of::<UnitStatePacked>(), 4);
    }

    #[test]
    fn test_spatial_grid_update_and_query() {
        let mut mgr = BatchUnitManager::new(1024.0, 1024.0, 128.0);
        let units = vec![
            UnitStatePacked {
                id: 1,
                x: 100.0,
                y: 0.0,
                z: 100.0,
                vx: 0.0,
                vz: 0.0,
                hp: 500.0,
                max_hp: 500.0,
                team_id: 0,
                def_id: 10,
                flags: 1,
            },
            UnitStatePacked {
                id: 2,
                x: 150.0,
                y: 0.0,
                z: 150.0,
                vx: 0.0,
                vz: 0.0,
                hp: 600.0,
                max_hp: 600.0,
                team_id: 1,
                def_id: 11,
                flags: 1,
            },
            UnitStatePacked {
                id: 3,
                x: 900.0,
                y: 0.0,
                z: 900.0,
                vx: 0.0,
                vz: 0.0,
                hp: 300.0,
                max_hp: 300.0,
                team_id: 0,
                def_id: 12,
                flags: 1,
            },
        ];

        mgr.update_batch(&units);

        let mut out = [0u32; 16];
        let found = mgr.query_radius(120.0, 120.0, 60.0, -1, &mut out);
        assert_eq!(found, 2);
        assert!(out[..found].contains(&1));
        assert!(out[..found].contains(&2));

        // Team filter test
        let found_team0 = mgr.query_radius(120.0, 120.0, 60.0, 0, &mut out);
        assert_eq!(found_team0, 1);
        assert_eq!(out[0], 1);
    }
}
