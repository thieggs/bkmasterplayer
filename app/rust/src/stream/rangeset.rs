//! Conjunto de intervalos de bytes `[início, fim)` já baixados.

#[derive(Debug, Default, Clone)]
pub struct RangeSet {
    /// Ordenados, sem sobreposição e sem intervalos adjacentes (sempre fundidos).
    ranges: Vec<(u64, u64)>,
}

impl RangeSet {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn insert(&mut self, start: u64, end: u64) {
        if start >= end {
            return;
        }
        let (mut s, mut e) = (start, end);
        let i = self.ranges.partition_point(|r| r.1 < s);
        let mut j = i;
        while j < self.ranges.len() && self.ranges[j].0 <= e {
            s = s.min(self.ranges[j].0);
            e = e.max(self.ranges[j].1);
            j += 1;
        }
        self.ranges.splice(i..j, std::iter::once((s, e)));
    }

    /// Se `pos` está coberto, retorna o fim do intervalo contíguo que o contém.
    pub fn contiguous_end(&self, pos: u64) -> Option<u64> {
        let i = self.ranges.partition_point(|r| r.1 <= pos);
        match self.ranges.get(i) {
            Some(&(a, b)) if a <= pos && pos < b => Some(b),
            _ => None,
        }
    }

    pub fn contains(&self, pos: u64) -> bool {
        self.contiguous_end(pos).is_some()
    }

    /// Primeiro byte `>= pos` (e `< total`) que ainda não foi baixado.
    pub fn first_missing_from(&self, pos: u64, total: u64) -> Option<u64> {
        if pos >= total {
            return None;
        }
        match self.contiguous_end(pos) {
            Some(end) if end >= total => None,
            Some(end) => Some(end),
            None => Some(pos),
        }
    }

    pub fn covered(&self) -> u64 {
        self.ranges.iter().map(|r| r.1 - r.0).sum()
    }

    pub fn is_complete(&self, total: u64) -> bool {
        total == 0 || (self.ranges.len() == 1 && self.ranges[0].0 == 0 && self.ranges[0].1 >= total)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn merges_overlapping_and_adjacent() {
        let mut r = RangeSet::new();
        r.insert(10, 20);
        r.insert(30, 40);
        r.insert(20, 30);
        assert_eq!(r.ranges, vec![(10, 40)]);
        r.insert(0, 5);
        r.insert(4, 11);
        assert_eq!(r.ranges, vec![(0, 40)]);
        assert!(r.is_complete(40));
        assert!(!r.is_complete(41));
    }

    #[test]
    fn missing_and_contiguous() {
        let mut r = RangeSet::new();
        r.insert(0, 100);
        r.insert(200, 300);
        assert_eq!(r.contiguous_end(50), Some(100));
        assert_eq!(r.contiguous_end(100), None);
        assert_eq!(r.first_missing_from(0, 300), Some(100));
        assert_eq!(r.first_missing_from(150, 300), Some(150));
        assert_eq!(r.first_missing_from(250, 300), None);
        assert_eq!(r.first_missing_from(250, 400), Some(300));
        assert_eq!(r.covered(), 200);
    }
}
