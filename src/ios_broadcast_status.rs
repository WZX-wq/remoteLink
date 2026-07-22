pub(crate) fn viewer_count_for(active: bool, connection_count: usize) -> usize {
    if active {
        connection_count
    } else {
        0
    }
}

#[cfg(test)]
mod tests {
    use super::viewer_count_for;

    #[test]
    fn viewer_count_is_hidden_when_broadcast_is_inactive() {
        assert_eq!(viewer_count_for(false, 3), 0);
        assert_eq!(viewer_count_for(true, 3), 3);
    }
}
