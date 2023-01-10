use core::ptr::NonNull;

use crate::cruby::{
    attr_index_t, rb_shape, rb_shape_get_iv_index, rb_shape_get_next, rb_shape_get_shape_by_id,
    rb_shape_get_shape_id, rb_shape_id, rb_shape_id_offset, rb_shape_transition_shape_capa,
    shape_id_t, ID, VALUE,
};

/// Guards access to an inner shape to ensure that it is checked before usage
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ShapeGuard {
    Root(Shape),
    Ivar(Shape),
    Frozen(Shape),
    CapacityChange(Shape),
    InitialCapacity(Shape),
    TObject(Shape),
    ObjTooComplex(Shape),
}

/// A Ruby object shape
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct Shape(NonNull<rb_shape>);

impl ShapeGuard {
    /// The inner shape
    pub fn value(self) -> Shape {
        match self {
            Self::Root(shape) => shape,
            Self::Ivar(shape) => shape,
            Self::Frozen(shape) => shape,
            Self::CapacityChange(shape) => shape,
            Self::InitialCapacity(shape) => shape,
            Self::TObject(shape) => shape,
            Self::ObjTooComplex(shape) => shape,
        }
    }
}

impl Shape {
    /// Get a guarded shape from a Ruby object
    pub fn of(obj: VALUE) -> Option<ShapeGuard> {
        let shape = match Shape::from_value(obj) {
            Some(shape) => shape,
            None => return None,
        };

        Some(shape.guard())
    }

    /// The offset of the shape id
    pub fn id_offset() -> i32 {
        unsafe { rb_shape_id_offset() }
    }

    /// The shape id
    pub fn id(&self) -> shape_id_t {
        unsafe { rb_shape_id(self.as_ptr()) }
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

    //// The shape type
    pub fn guard(self) -> ShapeGuard {
        match self.inner().type_ {
            0 => ShapeGuard::Root(self),
            1 => ShapeGuard::Ivar(self),
            2 => ShapeGuard::Frozen(self),
            3 => ShapeGuard::CapacityChange(self),
            4 => ShapeGuard::InitialCapacity(self),
            5 => ShapeGuard::TObject(self),
            6 => ShapeGuard::ObjTooComplex(self),
            _ => unreachable!(),
        }
    }

    /// The index of an instance variable
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
    pub fn get_next<T: Into<VALUE>, I: Into<ID>>(&self, obj: T, id: I) -> Option<ShapeGuard> {
        let raw = unsafe { rb_shape_get_next(self.0.as_ptr(), obj.into(), id.into()) };

        Self::from_raw(raw).map(Shape::guard)
    }

    /// Consume the shape and return the raw pointer
    pub fn into_raw(self) -> *mut rb_shape {
        self.0.as_ptr()
    }

    /// Get the raw pointer to the shape
    fn as_ptr(&self) -> *mut rb_shape {
        self.0.as_ptr()
    }

    /// Create a new shape from a Ruby object
    fn from_value(obj: VALUE) -> Option<Self> {
        let id = unsafe { rb_shape_get_shape_id(obj) };
        Self::from_raw(unsafe { rb_shape_get_shape_by_id(id) })
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
