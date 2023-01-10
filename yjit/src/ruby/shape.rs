use core::ptr::NonNull;

use crate::cruby::{rb_shape, rb_shape_get_shape_by_id, shape_id_t, rb_shape_transition_shape_capa, rb_shape_get_next, ID, VALUE, rb_shape_id, rb_shape_get_shape_id, rb_shape_get_iv_index, attr_index_t, rb_shape_id_offset, OBJ_TOO_COMPLEX_SHAPE_ID};

/// A Ruby object shape
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct Shape(NonNull<rb_shape>);

impl Shape {
  /// Create a new shape from a Ruby object
  pub fn of(obj: VALUE) -> Option<Self> {
    let shape_id = Self::id_of(obj);
    Self::from_raw(unsafe { rb_shape_get_shape_by_id(shape_id) })
  }

  // Get the shape id of a Ruby object
  pub fn id_of(obj: VALUE) -> shape_id_t {
    unsafe { rb_shape_get_shape_id(obj) }
  }

  /// The offset of the shape id
  pub fn id_offset() -> i32 {
    unsafe { rb_shape_id_offset() }
  }

  /// The shape id
  pub fn id(&self) -> shape_id_t {
    unsafe { rb_shape_id(self.as_ptr()) }
  }

  /// Whether the shape is too complex
  pub fn is_too_complex(&self) -> bool {
    self.id() == OBJ_TOO_COMPLEX_SHAPE_ID
  }

  /// Transition the shape to a new capacity
  pub fn transition_capacity(&mut self, new_capacity: u32) -> &mut Self {
    unsafe { rb_shape_transition_shape_capa(self.as_ptr(), new_capacity) };
    self
  }

  /// Whether the shape has the capacity to store the next iv index
  pub fn needs_extension(&self) -> bool {
    self.capacity() <= self.next_iv_index()
  }

  /// The number of slots in the shape
  pub fn capacity(&self) -> u32 {
    self.inner().capacity
  }

  pub fn get_iv_index(&self, ivar_name: ID) -> Option<attr_index_t> {
    let mut ivar_index = 0;

    if unsafe { rb_shape_get_iv_index(self.as_ptr(), ivar_name, &mut ivar_index) } {
      None
    } else {
      Some(ivar_index)
    }
  }

  /// The next instance variable index for the shape
  pub fn next_iv_index(&self) -> u32 {
    self.inner().next_iv_index
  }

  /// The next shape for a given object and id
  pub fn get_next<T: Into<VALUE>, I: Into<ID>>(&self, obj: T, id: I) -> Option<Self> {
    let raw = unsafe { rb_shape_get_next(self.0.as_ptr(), obj.into(), id.into()) };

    Self::from_raw(raw)
  }

  /// Consume the shape and return the raw pointer
  pub fn into_raw(self) -> *mut rb_shape {
    self.0.as_ptr()
  }

  /// Get the raw pointer to the shape
  fn as_ptr(&self) -> *mut rb_shape {
    self.0.as_ptr()
  }

  /// Create a new shape from a raw pointer
  fn from_raw(raw: *mut rb_shape) -> Option<Self> {
    NonNull::new(raw).map(Self)
  }

  #[inline]
  fn inner(&self) -> &rb_shape {
    unsafe { self.0.as_ref() }
  }
}
