--  Create declarations for synthesis.
--  Copyright (C) 2017 Tristan Gingold
--
--  This file is part of GHDL.
--
--  This program is free software; you can redistribute it and/or modify
--  it under the terms of the GNU General Public License as published by
--  the Free Software Foundation; either version 2 of the License, or
--  (at your option) any later version.
--
--  This program is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--  GNU General Public License for more details.
--
--  You should have received a copy of the GNU General Public License
--  along with this program; if not, write to the Free Software
--  Foundation, Inc., 51 Franklin Street - Fifth Floor, Boston,
--  MA 02110-1301, USA.

with Types; use Types;
with Mutils; use Mutils;
with Netlists; use Netlists;
with Netlists.Builders; use Netlists.Builders;
with Vhdl.Errors; use Vhdl.Errors;
with Vhdl.Utils; use Vhdl.Utils;
with Synth.Types; use Synth.Types;
with Synth.Values; use Synth.Values;
with Synth.Environment; use Synth.Environment;
with Synth.Expr; use Synth.Expr;
with Vhdl.Annotations; use Vhdl.Annotations;
with Simple_IO;
with Netlists.Dump;

package body Synth.Decls is
   procedure Synth_Anonymous_Subtype_Indication
     (Syn_Inst : Synth_Instance_Acc; Atype : Node);

   procedure Create_Var_Wire
     (Syn_Inst : Synth_Instance_Acc; Decl : Iir; Init : Value_Acc)
   is
      Val : constant Value_Acc := Get_Value (Syn_Inst, Decl);
      Value : Net;
      Ival : Net;
      W : Width;
      Name : Sname;
   begin
      case Val.Kind is
         when Value_Wire =>
            --  FIXME: get the width directly from the wire ?
            W := Get_Width (Syn_Inst, Get_Type (Decl));
            Name := New_Sname (Syn_Inst.Name, Get_Identifier (Decl));
            if Init /= null then
               Ival := Get_Net (Init, Get_Type (Decl));
               pragma Assert (Get_Width (Ival) = W);
               Value := Build_Isignal (Build_Context, Name, Ival);
            else
               Value := Build_Signal (Build_Context, Name, W);
            end if;
            Set_Wire_Gate (Val.W, Value);
         when others =>
            raise Internal_Error;
      end case;
   end Create_Var_Wire;

   procedure Synth_Type_Definition (Syn_Inst : Synth_Instance_Acc; Def : Node)
   is
      pragma Unreferenced (Syn_Inst);
   begin
      case Get_Kind (Def) is
         when Iir_Kind_Enumeration_Type_Definition =>
            declare
               Info : constant Sim_Info_Acc := Get_Info (Def);
               Enum_List : constant Node_Flist :=
                 Get_Enumeration_Literal_List (Def);
            begin
               if Is_Bit_Type (Def) then
                  Info.Width := 1;
               else
                  Info.Width :=
                    Uns32 (Clog2 (Uns64 (Get_Nbr_Elements (Enum_List))));
               end if;
            end;
         when Iir_Kind_Integer_Type_Definition
           | Iir_Kind_Floating_Type_Definition
           | Iir_Kind_Physical_Type_Definition
           | Iir_Kind_Array_Type_Definition =>
            null;
         when Iir_Kind_Access_Type_Definition
           | Iir_Kind_File_Type_Definition =>
            null;
         when others =>
            Error_Kind ("synth_type_definition", Def);
      end case;
   end Synth_Type_Definition;

   function Synth_Range_Constraint
     (Syn_Inst : Synth_Instance_Acc; Rng : Node) return Value_Acc is
   begin
      case Get_Kind (Rng) is
         when Iir_Kind_Range_Expression =>
            --  FIXME: check range.
            return Synth_Range_Expression (Syn_Inst, Rng);
         when others =>
            Error_Kind ("synth_range_constraint", Rng);
      end case;
   end Synth_Range_Constraint;

   procedure Synth_Subtype_Indication_If_Anonymous
     (Syn_Inst : Synth_Instance_Acc; Atype : Node) is
   begin
      if Get_Type_Declarator (Atype) = Null_Node then
         Synth_Subtype_Indication (Syn_Inst, Atype);
      end if;
   end Synth_Subtype_Indication_If_Anonymous;

   procedure Synth_Subtype_Indication
     (Syn_Inst : Synth_Instance_Acc; Atype : Node) is
   begin
      case Get_Kind (Atype) is
         when Iir_Kind_Array_Subtype_Definition =>
            --  LRM93 12.3.1.3
            --  The elaboration of an index constraint consists of the
            --  declaration of each of the discrete ranges in the index
            --  constraint in some order that is not defined by the language.
            Synth_Subtype_Indication_If_Anonymous
              (Syn_Inst, Get_Element_Subtype (Atype));
            declare
               St_Indexes : constant Iir_Flist :=
                 Get_Index_Subtype_List (Atype);
               St_El : Iir;
               Bnds : Value_Bound_Array_Acc;
            begin
               --  FIXME: partially constrained arrays, subtype in indexes...
               Bnds := Create_Value_Bound_Array
                 (Iir_Index32 (Get_Nbr_Elements (St_Indexes)));
               for I in Flist_First .. Flist_Last (St_Indexes) loop
                  St_El := Get_Index_Type (St_Indexes, I);
                  Bnds.D (Iir_Index32 (I + 1)) :=
                    Synth_Bounds_From_Range (Syn_Inst, St_El);
               end loop;
               Create_Object (Syn_Inst, Atype,
                              Create_Value_Bounds (Bnds));
            end;
         when Iir_Kind_Integer_Subtype_Definition
           | Iir_Kind_Floating_Subtype_Definition
           | Iir_Kind_Physical_Subtype_Definition
           | Iir_Kind_Enumeration_Subtype_Definition =>
            declare
               Val : Value_Acc;
            begin
               Val := Synth_Range_Constraint
                 (Syn_Inst, Get_Range_Constraint (Atype));
               Create_Object (Syn_Inst, Atype, Unshare (Val, Instance_Pool));
            end;
         when others =>
            Error_Kind ("synth_subtype_indication", Atype);
      end case;
   end Synth_Subtype_Indication;

   procedure Synth_Anonymous_Subtype_Indication
     (Syn_Inst : Synth_Instance_Acc; Atype : Node) is
   begin
      if Atype = Null_Node
        or else Get_Type_Declarator (Atype) /= Null_Node
      then
         return;
      end if;
      Synth_Subtype_Indication (Syn_Inst, Atype);
   end Synth_Anonymous_Subtype_Indication;

   pragma Unreferenced (Synth_Anonymous_Subtype_Indication);

   function Get_Declaration_Type (Decl : Node) return Node
   is
      Ind : constant Node := Get_Subtype_Indication (Decl);
      Atype : Node;
   begin
      if Ind = Null_Node then
         --  No subtype indication; use the same type.
         return Null_Node;
      end if;
      Atype := Ind;
      loop
         case Get_Kind (Atype) is
            when Iir_Kinds_Denoting_Name =>
               Atype := Get_Named_Entity (Atype);
            when Iir_Kind_Subtype_Declaration
              | Iir_Kind_Type_Declaration =>
               return Null_Node;
            when Iir_Kind_Array_Subtype_Definition
              | Iir_Kind_Integer_Subtype_Definition
              | Iir_Kind_Floating_Subtype_Definition
              | Iir_Kind_Physical_Subtype_Definition
              | Iir_Kind_Enumeration_Subtype_Definition =>
               return Atype;
            when others =>
               Error_Kind ("get_declaration_type", Atype);
         end case;
      end loop;
   end Get_Declaration_Type;

   procedure Synth_Declaration_Type
     (Syn_Inst : Synth_Instance_Acc; Decl : Node)
   is
      Atype : constant Node := Get_Declaration_Type (Decl);
   begin
      if Atype = Null_Node then
         return;
      end if;
      Synth_Subtype_Indication (Syn_Inst, Atype);
   end Synth_Declaration_Type;

   procedure Synth_Constant_Declaration
     (Syn_Inst : Synth_Instance_Acc; Decl : Node)
   is
      Deferred_Decl : constant Node := Get_Deferred_Declaration (Decl);
      First_Decl : Node;
      Val : Value_Acc;
   begin
      if Deferred_Decl = Null_Node
        or else Get_Deferred_Declaration_Flag (Decl)
      then
         --  Create the object (except for full declaration of a
         --  deferred constant).
         Synth_Declaration_Type (Syn_Inst, Decl);
         Create_Object (Syn_Inst, Decl, null);
      end if;
      --  Initialize the value (except for a deferred declaration).
      if Deferred_Decl = Null_Node then
         First_Decl := Decl;
      elsif not Get_Deferred_Declaration_Flag (Decl) then
         First_Decl := Deferred_Decl;
      else
         First_Decl := Null_Node;
      end if;
      if First_Decl /= Null_Node then
         Val := Synth_Expression_With_Type
           (Syn_Inst, Get_Default_Value (Decl), Get_Type (Decl));
         Syn_Inst.Objects (Get_Info (First_Decl).Slot) := Val;
      end if;
   end Synth_Constant_Declaration;

   procedure Synth_Attribute_Specification
     (Syn_Inst : Synth_Instance_Acc; Decl : Node)
   is
      Value : Iir_Attribute_Value;
      Val : Value_Acc;
   begin
      Value := Get_Attribute_Value_Spec_Chain (Decl);
      while Value /= Null_Iir loop
         --  2. The expression is evaluated to determine the value
         --     of the attribute.
         --     It is an error if the value of the expression does not
         --     belong to the subtype of the attribute; if the
         --     attribute is of an array type, then an implicit
         --     subtype conversion is first performed on the value,
         --     unless the attribute's subtype indication denotes an
         --     unconstrained array type.
         Val := Synth_Expression_With_Type
           (Syn_Inst, Get_Expression (Decl), Get_Type (Value));
         --  Check_Constraints (Instance, Val, Attr_Type, Decl);

         --  3. A new instance of the designated attribute is created
         --     and associated with each of the affected items.
         --
         --  4. Each new attribute instance is assigned the value of
         --     the expression.
         Create_Object (Syn_Inst, Value, Val);
         --  Unshare (Val, Instance_Pool);

         Value := Get_Spec_Chain (Value);
      end loop;
   end Synth_Attribute_Specification;


   procedure Synth_Declaration (Syn_Inst : Synth_Instance_Acc; Decl : Node) is
   begin
      case Get_Kind (Decl) is
         when Iir_Kind_Variable_Declaration =>
            Synth_Declaration_Type (Syn_Inst, Decl);
            declare
               Def : constant Iir := Get_Default_Value (Decl);
               --  Slot : constant Object_Slot_Type := Get_Info (Decl).Slot;
               Init : Value_Acc;
            begin
               Make_Object (Syn_Inst, Wire_Variable, Decl);
               if Is_Valid (Def) then
                  Init := Synth_Expression_With_Type
                    (Syn_Inst, Def, Get_Type (Decl));
               else
                  Init := null;
               end if;
               Create_Var_Wire (Syn_Inst, Decl, Init);
            end;
         when Iir_Kind_Interface_Variable_Declaration =>
            --  Ignore default value.
            Make_Object (Syn_Inst, Wire_Variable, Decl);
            Create_Var_Wire (Syn_Inst, Decl, null);
         when Iir_Kind_Constant_Declaration =>
            Synth_Constant_Declaration (Syn_Inst, Decl);
         when Iir_Kind_Signal_Declaration =>
            Synth_Declaration_Type (Syn_Inst, Decl);
            declare
               Def : constant Iir := Get_Default_Value (Decl);
               --  Slot : constant Object_Slot_Type := Get_Info (Decl).Slot;
               Init : Value_Acc;
            begin
               Make_Object (Syn_Inst, Wire_Signal, Decl);
               if Is_Valid (Def) then
                  Init := Synth_Expression_With_Type
                    (Syn_Inst, Def, Get_Type (Decl));
               else
                  Init := null;
               end if;
               Create_Var_Wire (Syn_Inst, Decl, Init);
            end;
         when Iir_Kind_Anonymous_Signal_Declaration =>
            Make_Object (Syn_Inst, Wire_Signal, Decl);
            Create_Var_Wire (Syn_Inst, Decl, null);
         when Iir_Kind_Procedure_Declaration
           | Iir_Kind_Function_Declaration =>
            --  TODO: elaborate interfaces
            null;
         when Iir_Kind_Procedure_Body
           | Iir_Kind_Function_Body =>
            null;
         when Iir_Kind_Non_Object_Alias_Declaration =>
            null;
         when Iir_Kind_Attribute_Declaration =>
            --  Nothing to do: the type is a type_mark, not a subtype
            --  indication.
            null;
         when Iir_Kind_Attribute_Specification =>
            Synth_Attribute_Specification (Syn_Inst, Decl);
         when Iir_Kind_Type_Declaration
           | Iir_Kind_Anonymous_Type_Declaration =>
            Synth_Type_Definition (Syn_Inst, Get_Type_Definition (Decl));
         when  Iir_Kind_Subtype_Declaration =>
            Synth_Declaration_Type (Syn_Inst, Decl);
         when Iir_Kind_Component_Declaration =>
            null;
         when Iir_Kind_File_Declaration =>
            null;
         when others =>
            Error_Kind ("synth_declaration", Decl);
      end case;
   end Synth_Declaration;

   procedure Synth_Declarations (Syn_Inst : Synth_Instance_Acc; Decls : Iir)
   is
      Decl : Iir;
   begin
      Decl := Decls;
      Simple_IO.Put("Processing decl " & Iir'Image(Decl) & " >>  ");
      Netlists.Dump.Dump_Name(Syn_Inst.Name);
      while Is_Valid (Decl) loop
         Synth_Declaration (Syn_Inst, Decl);

         Decl := Get_Chain (Decl);
      end loop;
   end Synth_Declarations;
end Synth.Decls;
