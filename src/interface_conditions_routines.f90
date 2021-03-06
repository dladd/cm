!> \file
!> \author Chris Bradley
!> \brief This module contains all interface conditions routines.
!>
!> \section LICENSE
!>
!> Version: MPL 1.1/GPL 2.0/LGPL 2.1
!>
!> The contents of this file are subject to the Mozilla Public License
!> Version 1.1 (the "License"); you may not use this file except in
!> compliance with the License. You may obtain a copy of the License at
!> http://www.mozilla.org/MPL/
!>
!> Software distributed under the License is distributed on an "AS IS"
!> basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
!> License for the specific language governing rights and limitations
!> under the License.
!>
!> The Original Code is OpenCMISS
!>
!> The Initial Developer of the Original Code is University of Auckland,
!> Auckland, New Zealand, the University of Oxford, Oxford, United
!> Kingdom and King's College, London, United Kingdom. Portions created
!> by the University of Auckland, the University of Oxford and King's
!> College, London are Copyright (C) 2007-2010 by the University of
!> Auckland, the University of Oxford and King's College, London.
!> All Rights Reserved.
!>
!> Contributor(s):
!>
!> Alternatively, the contents of this file may be used under the terms of
!> either the GNU General Public License Version 2 or later (the "GPL"), or
!> the GNU Lesser General Public License Version 2.1 or later (the "LGPL"),
!> in which case the provisions of the GPL or the LGPL are applicable instead
!> of those above. If you wish to allow use of your version of this file only
!> under the terms of either the GPL or the LGPL, and not to allow others to
!> use your version of this file under the terms of the MPL, indicate your
!> decision by deleting the provisions above and replace them with the notice
!> and other provisions required by the GPL or the LGPL. If you do not delete
!> the provisions above, a recipient may use your version of this file under
!> the terms of any one of the MPL, the GPL or the LGPL.
!>

!>This module contains all interface conditions routines.
MODULE INTERFACE_CONDITIONS_ROUTINES

  USE BASE_ROUTINES
  USE BASIS_ROUTINES
  USE FIELD_ROUTINES
  USE INPUT_OUTPUT
  USE INTERFACE_CONDITIONS_CONSTANTS
  USE INTERFACE_EQUATIONS_ROUTINES
  USE INTERFACE_MAPPING_ROUTINES
  USE INTERFACE_MATRICES_ROUTINES
  USE ISO_VARYING_STRING
  USE KINDS
  USE MATRIX_VECTOR
  USE STRINGS
  USE TIMER
  USE TYPES

  IMPLICIT NONE

  !Module types

  !Module variables

  !Interfaces

  PUBLIC INTERFACE_CONDITION_CREATE_FINISH,INTERFACE_CONDITION_CREATE_START

  PUBLIC INTERFACE_CONDITION_DEPENDENT_VARIABLE_ADD

  PUBLIC INTERFACE_CONDITION_DESTROY

  PUBLIC INTERFACE_CONDITION_EQUATIONS_CREATE_FINISH,INTERFACE_CONDITION_EQUATIONS_CREATE_START

  PUBLIC INTERFACE_CONDITION_EQUATIONS_DESTROY
  
  PUBLIC InterfaceCondition_IntegrationTypeGet,InterfaceCondition_IntegrationTypeSet

  PUBLIC INTERFACE_CONDITION_LAGRANGE_FIELD_CREATE_FINISH,INTERFACE_CONDITION_LAGRANGE_FIELD_CREATE_START

  PUBLIC INTERFACE_CONDITION_METHOD_GET,INTERFACE_CONDITION_METHOD_SET

  PUBLIC INTERFACE_CONDITION_OPERATOR_GET,INTERFACE_CONDITION_OPERATOR_SET

  PUBLIC INTERFACE_CONDITION_USER_NUMBER_FIND

  PUBLIC INTERFACE_CONDITIONS_FINALISE,INTERFACE_CONDITIONS_INITIALISE

CONTAINS

  !
  !================================================================================================================================
  !

  !>Assembles the equations for an interface condition.
  SUBROUTINE INTERFACE_CONDITION_ASSEMBLE(INTERFACE_CONDITION,ERR,ERROR,*)

    !Argument variables
    TYPE(INTERFACE_CONDITION_TYPE), POINTER :: INTERFACE_CONDITION !<A pointer to the interface condition to assemble the equations for.
    INTEGER(INTG), INTENT(OUT) :: ERR !<The error code
    TYPE(VARYING_STRING), INTENT(OUT) :: ERROR !<The error string
    !Local Variables
    TYPE(INTERFACE_EQUATIONS_TYPE), POINTER :: INTERFACE_EQUATIONS
    TYPE(VARYING_STRING) :: LOCAL_ERROR
 
    CALL ENTERS("INTERFACE_CONDITION_ASSEMBLE",ERR,ERROR,*999)

    IF(ASSOCIATED(INTERFACE_CONDITION)) THEN
      INTERFACE_EQUATIONS=>INTERFACE_CONDITION%INTERFACE_EQUATIONS
      IF(ASSOCIATED(INTERFACE_EQUATIONS)) THEN
        IF(INTERFACE_EQUATIONS%INTERFACE_EQUATIONS_FINISHED) THEN
          SELECT CASE(INTERFACE_CONDITION%METHOD)
          CASE(INTERFACE_CONDITION_LAGRANGE_MULTIPLIERS_METHOD)
            CALL INTERFACE_CONDITION_ASSEMBLE_FEM(INTERFACE_CONDITION,ERR,ERROR,*999)
          CASE(INTERFACE_CONDITION_AUGMENTED_LAGRANGE_METHOD)
            CALL FLAG_ERROR("Not implemented.",ERR,ERROR,*999)
          CASE(INTERFACE_CONDITION_PENALTY_METHOD)
            CALL FLAG_ERROR("Not implemented.",ERR,ERROR,*999)
          CASE(INTERFACE_CONDITION_POINT_TO_POINT_METHOD)
            CALL FLAG_ERROR("Not implemented.",ERR,ERROR,*999)
          CASE DEFAULT
            LOCAL_ERROR="The interface condition method of "// &
              & TRIM(NUMBER_TO_VSTRING(INTERFACE_CONDITION%METHOD,"*",ERR,ERROR))// &
              & " is invalid."
            CALL FLAG_ERROR(LOCAL_ERROR,ERR,ERROR,*999)
          END SELECT
        ELSE
          CALL FLAG_ERROR("Interface equations have not been finished.",ERR,ERROR,*999)
        ENDIF
      ELSE
        CALL FLAG_ERROR("Interface condition interface equations is not associated.",ERR,ERROR,*999)
      ENDIF      
    ELSE
      CALL FLAG_ERROR("Interface condition is not associated.",ERR,ERROR,*999)
    ENDIF
       
    CALL EXITS("INTERFACE_CONDITION_ASSEMBLE")
    RETURN
999 CALL ERRORS("INTERFACE_CONDITION_ASSEMBLE",ERR,ERROR)
    CALL EXITS("INTERFACE_CONDITION_ASSEMBLE")
    RETURN 1
  END SUBROUTINE INTERFACE_CONDITION_ASSEMBLE

  !
  !================================================================================================================================
  !
  
  !>Assembles the interface matricesand rhs for using the finite element method.
  SUBROUTINE INTERFACE_CONDITION_ASSEMBLE_FEM(INTERFACE_CONDITION,ERR,ERROR,*)

    !Argument variables
    TYPE(INTERFACE_CONDITION_TYPE), POINTER :: INTERFACE_CONDITION !<A pointer to the interface condition to assemble the equations for
    INTEGER(INTG), INTENT(OUT) :: ERR !<The error code
    TYPE(VARYING_STRING), INTENT(OUT) :: ERROR !<The error string
    !Local Variables
    INTEGER(INTG) :: element_idx,ne,NUMBER_OF_TIMES
    REAL(SP) :: ELEMENT_USER_ELAPSED,ELEMENT_SYSTEM_ELAPSED,USER_ELAPSED,USER_TIME1(1),USER_TIME2(1),USER_TIME3(1),USER_TIME4(1), &
      & USER_TIME5(1),USER_TIME6(1),SYSTEM_ELAPSED,SYSTEM_TIME1(1),SYSTEM_TIME2(1),SYSTEM_TIME3(1),SYSTEM_TIME4(1), &
      & SYSTEM_TIME5(1),SYSTEM_TIME6(1)
    TYPE(DOMAIN_MAPPING_TYPE), POINTER :: ELEMENTS_MAPPING
    TYPE(INTERFACE_EQUATIONS_TYPE), POINTER :: INTERFACE_EQUATIONS
    TYPE(INTERFACE_MATRICES_TYPE), POINTER :: INTERFACE_MATRICES
    TYPE(FIELD_TYPE), POINTER :: LAGRANGE_FIELD
    
!#ifdef TAUPROF
!    CHARACTER(28) :: CVAR
!    INTEGER :: PHASE(2) = (/ 0, 0 /)
!    SAVE PHASE
!#endif

    CALL ENTERS("INTERFACE_CONDITION_ASSEMBLE_FEM",ERR,ERROR,*999)

    IF(ASSOCIATED(INTERFACE_CONDITION)) THEN
      IF(ASSOCIATED(INTERFACE_CONDITION%LAGRANGE)) THEN
        LAGRANGE_FIELD=>INTERFACE_CONDITION%LAGRANGE%LAGRANGE_FIELD
        IF(ASSOCIATED(LAGRANGE_FIELD)) THEN
          INTERFACE_EQUATIONS=>INTERFACE_CONDITION%INTERFACE_EQUATIONS
          IF(ASSOCIATED(INTERFACE_EQUATIONS)) THEN
            INTERFACE_MATRICES=>INTERFACE_EQUATIONS%INTERFACE_MATRICES
            IF(ASSOCIATED(INTERFACE_MATRICES)) THEN
              IF(INTERFACE_EQUATIONS%OUTPUT_TYPE>=INTERFACE_EQUATIONS_TIMING_OUTPUT) THEN
                CALL CPU_TIMER(USER_CPU,USER_TIME1,ERR,ERROR,*999)
                CALL CPU_TIMER(SYSTEM_CPU,SYSTEM_TIME1,ERR,ERROR,*999)
              ENDIF
              !Initialise the matrices and rhs vector
#ifdef TAUPROF
              CALL TAU_STATIC_PHASE_START("INTERFACE_MATRICES_VALUES_INITIALISE()")
#endif
              CALL INTERFACE_MATRICES_VALUES_INITIALISE(INTERFACE_MATRICES,0.0_DP,ERR,ERROR,*999)
#ifdef TAUPROF
              CALL TAU_STATIC_PHASE_STOP("INTERFACE_MATRICES_VALUES_INITIALISE()")
#endif
              !Assemble the elements
              !Allocate the element matrices 
#ifdef TAUPROF
              CALL TAU_STATIC_PHASE_START("InterfaceMatrices_ElementInitialise()")
#endif
              CALL InterfaceMatrices_ElementInitialise(INTERFACE_MATRICES,ERR,ERROR,*999)
              ELEMENTS_MAPPING=>LAGRANGE_FIELD%DECOMPOSITION%DOMAIN(LAGRANGE_FIELD%DECOMPOSITION%MESH_COMPONENT_NUMBER)%PTR% &
                & MAPPINGS%ELEMENTS
#ifdef TAUPROF
              CALL TAU_STATIC_PHASE_STOP("InterfaceMatrices_ElementInitialise()")
#endif
              !Output timing information if required
              IF(INTERFACE_EQUATIONS%OUTPUT_TYPE>=INTERFACE_EQUATIONS_TIMING_OUTPUT) THEN
                CALL CPU_TIMER(USER_CPU,USER_TIME2,ERR,ERROR,*999)
                CALL CPU_TIMER(SYSTEM_CPU,SYSTEM_TIME2,ERR,ERROR,*999)
                USER_ELAPSED=USER_TIME2(1)-USER_TIME1(1)
                SYSTEM_ELAPSED=SYSTEM_TIME2(1)-SYSTEM_TIME1(1)
                CALL WRITE_STRING_VALUE(GENERAL_OUTPUT_TYPE,"User time for interface equations setup and initialisation = ", &
                  & USER_ELAPSED,ERR,ERROR,*999)
                CALL WRITE_STRING_VALUE(GENERAL_OUTPUT_TYPE,"System time for interface equations setup and initialisation = ", &
                  & SYSTEM_ELAPSED,ERR,ERROR,*999)
                ELEMENT_USER_ELAPSED=0.0_SP
                ELEMENT_SYSTEM_ELAPSED=0.0_SP
              ENDIF
              NUMBER_OF_TIMES=0
              !Loop over the internal elements

#ifdef TAUPROF
              CALL TAU_STATIC_PHASE_START("Internal Elements Loop")
#endif
              DO element_idx=ELEMENTS_MAPPING%INTERNAL_START,ELEMENTS_MAPPING%INTERNAL_FINISH
!#ifdef TAUPROF
!              WRITE (CVAR,'(a23,i3)') 'Internal Elements Loop ',element_idx
!              CALL TAU_PHASE_CREATE_DYNAMIC(PHASE,CVAR)
!              CALL TAU_PHASE_START(PHASE)
!#endif
                ne=ELEMENTS_MAPPING%DOMAIN_LIST(element_idx)
                NUMBER_OF_TIMES=NUMBER_OF_TIMES+1
                CALL InterfaceMatrices_ElementCalculate(INTERFACE_MATRICES,ne,ERR,ERROR,*999)
                CALL INTERFACE_CONDITION_FINITE_ELEMENT_CALCULATE(INTERFACE_CONDITION,ne,ERR,ERROR,*999)
                CALL INTERFACE_MATRICES_ELEMENT_ADD(INTERFACE_MATRICES,ERR,ERROR,*999)
!#ifdef TAUPROF
!              CALL TAU_PHASE_STOP(PHASE)
!#endif
              ENDDO !element_idx
#ifdef TAUPROF
              CALL TAU_STATIC_PHASE_STOP("Internal Elements Loop")
#endif

              !Output timing information if required
              IF(INTERFACE_EQUATIONS%OUTPUT_TYPE>=INTERFACE_EQUATIONS_TIMING_OUTPUT) THEN
                CALL CPU_TIMER(USER_CPU,USER_TIME3,ERR,ERROR,*999)
                CALL CPU_TIMER(SYSTEM_CPU,SYSTEM_TIME3,ERR,ERROR,*999)
                USER_ELAPSED=USER_TIME3(1)-USER_TIME2(1)
                SYSTEM_ELAPSED=SYSTEM_TIME3(1)-SYSTEM_TIME2(1)
                ELEMENT_USER_ELAPSED=USER_ELAPSED
                ELEMENT_SYSTEM_ELAPSED=SYSTEM_ELAPSED
                CALL WRITE_STRING_VALUE(GENERAL_OUTPUT_TYPE,"User time for internal interface equations assembly = ", &
                  & USER_ELAPSED, ERR,ERROR,*999)
                CALL WRITE_STRING_VALUE(GENERAL_OUTPUT_TYPE,"System time for internal interface equations assembly = ", &
                  & SYSTEM_ELAPSED,ERR,ERROR,*999)
              ENDIF
              !Output timing information if required
              IF(INTERFACE_EQUATIONS%OUTPUT_TYPE>=INTERFACE_EQUATIONS_TIMING_OUTPUT) THEN
                CALL CPU_TIMER(USER_CPU,USER_TIME4,ERR,ERROR,*999)
                CALL CPU_TIMER(SYSTEM_CPU,SYSTEM_TIME4,ERR,ERROR,*999)
                USER_ELAPSED=USER_TIME4(1)-USER_TIME3(1)
                SYSTEM_ELAPSED=SYSTEM_TIME4(1)-SYSTEM_TIME3(1)
                CALL WRITE_STRING_VALUE(GENERAL_OUTPUT_TYPE,"User time for parameter transfer completion = ",USER_ELAPSED, &
                  & ERR,ERROR,*999)
                CALL WRITE_STRING_VALUE(GENERAL_OUTPUT_TYPE,"System time for parameter transfer completion = ",SYSTEM_ELAPSED, &
                & ERR,ERROR,*999)              
              ENDIF
              !Loop over the boundary and ghost elements
#ifdef TAUPROF
              CALL TAU_STATIC_PHASE_START("Boundary and Ghost Elements Loop")
#endif
              DO element_idx=ELEMENTS_MAPPING%BOUNDARY_START,ELEMENTS_MAPPING%GHOST_FINISH
                ne=ELEMENTS_MAPPING%DOMAIN_LIST(element_idx)
                NUMBER_OF_TIMES=NUMBER_OF_TIMES+1
                CALL InterfaceMatrices_ElementCalculate(INTERFACE_MATRICES,ne,ERR,ERROR,*999)
                CALL INTERFACE_CONDITION_FINITE_ELEMENT_CALCULATE(INTERFACE_CONDITION,ne,ERR,ERROR,*999)
                CALL INTERFACE_MATRICES_ELEMENT_ADD(INTERFACE_MATRICES,ERR,ERROR,*999)
              ENDDO !element_idx
#ifdef TAUPROF
              CALL TAU_STATIC_PHASE_STOP("Boundary and Ghost Elements Loop")
#endif
              !Output timing information if required
              IF(INTERFACE_EQUATIONS%OUTPUT_TYPE>=INTERFACE_EQUATIONS_TIMING_OUTPUT) THEN
                CALL CPU_TIMER(USER_CPU,USER_TIME5,ERR,ERROR,*999)
                CALL CPU_TIMER(SYSTEM_CPU,SYSTEM_TIME5,ERR,ERROR,*999)
                USER_ELAPSED=USER_TIME5(1)-USER_TIME4(1)
                SYSTEM_ELAPSED=SYSTEM_TIME5(1)-SYSTEM_TIME4(1)
                ELEMENT_USER_ELAPSED=ELEMENT_USER_ELAPSED+USER_ELAPSED
                ELEMENT_SYSTEM_ELAPSED=ELEMENT_SYSTEM_ELAPSED+USER_ELAPSED
                CALL WRITE_STRING_VALUE(GENERAL_OUTPUT_TYPE,"User time for boundary+ghost equations assembly = ",USER_ELAPSED, &
                  & ERR,ERROR,*999)
                CALL WRITE_STRING_VALUE(GENERAL_OUTPUT_TYPE,"System time for boundary+ghost equations assembly = ",SYSTEM_ELAPSED, &
                  & ERR,ERROR,*999)
                IF(NUMBER_OF_TIMES>0) THEN
                  CALL WRITE_STRING_VALUE(GENERAL_OUTPUT_TYPE,"Average element user time for equations assembly = ", &
                    & ELEMENT_USER_ELAPSED/NUMBER_OF_TIMES,ERR,ERROR,*999)
                  CALL WRITE_STRING_VALUE(GENERAL_OUTPUT_TYPE,"Average element system time for equations assembly = ", &
                    & ELEMENT_SYSTEM_ELAPSED/NUMBER_OF_TIMES,ERR,ERROR,*999)
                ENDIF
              ENDIF
              !Finalise the element matrices
#ifdef TAUPROF
              CALL TAU_STATIC_PHASE_START("INTERFACE_MATRICES_ELEMENT_FINALISE()")
#endif
              CALL INTERFACE_MATRICES_ELEMENT_FINALISE(INTERFACE_MATRICES,ERR,ERROR,*999)
#ifdef TAUPROF
              CALL TAU_STATIC_PHASE_STOP("INTERFACE_MATRICES_ELEMENT_FINALISE()")
#endif
              !Output equations matrices and vector if required
              IF(INTERFACE_EQUATIONS%OUTPUT_TYPE>=INTERFACE_EQUATIONS_MATRIX_OUTPUT) THEN
                CALL INTERFACE_MATRICES_OUTPUT(GENERAL_OUTPUT_TYPE,INTERFACE_MATRICES,ERR,ERROR,*999)
              ENDIF
              !Output timing information if required
              IF(INTERFACE_EQUATIONS%OUTPUT_TYPE>=INTERFACE_EQUATIONS_TIMING_OUTPUT) THEN
                CALL CPU_TIMER(USER_CPU,USER_TIME6,ERR,ERROR,*999)
                CALL CPU_TIMER(SYSTEM_CPU,SYSTEM_TIME6,ERR,ERROR,*999)
                USER_ELAPSED=USER_TIME6(1)-USER_TIME1(1)
                SYSTEM_ELAPSED=SYSTEM_TIME6(1)-SYSTEM_TIME1(1)
                CALL WRITE_STRING(GENERAL_OUTPUT_TYPE,"***",ERR,ERROR,*999)
                CALL WRITE_STRING_VALUE(GENERAL_OUTPUT_TYPE,"Total user time for equations assembly = ",USER_ELAPSED, &
                  & ERR,ERROR,*999)
                CALL WRITE_STRING_VALUE(GENERAL_OUTPUT_TYPE,"Total system time for equations assembly = ",SYSTEM_ELAPSED, &
                  & ERR,ERROR,*999)
                CALL WRITE_STRING(GENERAL_OUTPUT_TYPE,"***",ERR,ERROR,*999)
              ENDIF
            ELSE
              CALL FLAG_ERROR("Interface matrices is not associated.",ERR,ERROR,*999)
            ENDIF
          ELSE
            CALL FLAG_ERROR("Interface matrices is not associated.",ERR,ERROR,*999)
          ENDIF
        ELSE
          CALL FLAG_ERROR("Lagrange field is not associated.",ERR,ERROR,*999)
        ENDIF
      ELSE
        CALL FLAG_ERROR("Interface condition Lagrange is not associated.",ERR,ERROR,*999)
      ENDIF
    ELSE
      CALL FLAG_ERROR("Interface condition is not associated",ERR,ERROR,*999)
    ENDIF
       
    CALL EXITS("INTERFACE_CONDITION_ASSEMBLE_FEM")
    RETURN
999 CALL ERRORS("INTERFACE_CONDITION_ASSEMBLE_FEM",ERR,ERROR)
    CALL EXITS("INTERFACE_CONDITION_ASSEMBLE_FEM")
    RETURN 1
  END SUBROUTINE INTERFACE_CONDITION_ASSEMBLE_FEM

  !
  !==================================================================================================================================
  !

  !>Finishes the process of creating an interface condition. \see OPENCMISS::CMISSInterfaceConditionCreateStart
  SUBROUTINE INTERFACE_CONDITION_CREATE_FINISH(INTERFACE_CONDITION,ERR,ERROR,*)

    !Argument variables
    TYPE(INTERFACE_CONDITION_TYPE), POINTER :: INTERFACE_CONDITION !<A pointer to the interface condition to finish creating
    INTEGER(INTG), INTENT(OUT) :: ERR !<The error code
    TYPE(VARYING_STRING), INTENT(OUT) :: ERROR !<The error string
    !Local Variables
    INTEGER(INTG) :: mesh_idx,mesh_idx_count,NUMBER_OF_COMPONENTS,variable_idx
    INTEGER(INTG), POINTER :: NEW_VARIABLE_MESH_INDICES(:)
    TYPE(FIELD_VARIABLE_TYPE), POINTER :: FIELD_VARIABLE
    TYPE(FIELD_VARIABLE_PTR_TYPE), POINTER :: NEW_FIELD_VARIABLES(:)
    TYPE(INTERFACE_TYPE), POINTER :: INTERFACE
    TYPE(INTERFACE_DEPENDENT_TYPE), POINTER :: INTERFACE_DEPENDENT
    TYPE(VARYING_STRING) :: LOCAL_ERROR
    
    NULLIFY(NEW_FIELD_VARIABLES)
    NULLIFY(NEW_VARIABLE_MESH_INDICES)
    
    CALL ENTERS("INTERFACE_CONDITION_CREATE_FINISH",ERR,ERROR,*999)

    IF(ASSOCIATED(INTERFACE_CONDITION)) THEN
      IF(INTERFACE_CONDITION%INTERFACE_CONDITION_FINISHED) THEN
        CALL FLAG_ERROR("Interface condition has already been finished.",ERR,ERROR,*999)
      ELSE
        INTERFACE=>INTERFACE_CONDITION%INTERFACE
        IF(ASSOCIATED(INTERFACE)) THEN
          !Test various inputs have been set up.
          SELECT CASE(INTERFACE_CONDITION%METHOD)
          CASE(INTERFACE_CONDITION_LAGRANGE_MULTIPLIERS_METHOD)
            INTERFACE_DEPENDENT=>INTERFACE_CONDITION%DEPENDENT
            IF(ASSOCIATED(INTERFACE_DEPENDENT)) THEN
              !Check the dependent field variables have been set.
              IF(INTERFACE_DEPENDENT%NUMBER_OF_DEPENDENT_VARIABLES<2) THEN
                LOCAL_ERROR="The number of added dependent variables of "// &
                  & TRIM(NUMBER_TO_VSTRING(INTERFACE_DEPENDENT%NUMBER_OF_DEPENDENT_VARIABLES,"*",ERR,ERROR))// &
                  & " is invalid. The number must be >= 2."
                CALL FLAG_ERROR(LOCAL_ERROR,ERR,ERROR,*999)
              ENDIF
              SELECT CASE(INTERFACE_CONDITION%OPERATOR)
              CASE(INTERFACE_CONDITION_FIELD_CONTINUITY_OPERATOR)
                !Check that the dependent variables have the same number of components
                FIELD_VARIABLE=>INTERFACE_DEPENDENT%FIELD_VARIABLES(1)%PTR
                IF(ASSOCIATED(FIELD_VARIABLE)) THEN
                  NUMBER_OF_COMPONENTS=FIELD_VARIABLE%NUMBER_OF_COMPONENTS
                  DO variable_idx=2,INTERFACE_DEPENDENT%NUMBER_OF_DEPENDENT_VARIABLES
                    FIELD_VARIABLE=>INTERFACE_DEPENDENT%FIELD_VARIABLES(variable_idx)%PTR
                    IF(ASSOCIATED(FIELD_VARIABLE)) THEN
                      IF(FIELD_VARIABLE%NUMBER_OF_COMPONENTS/=NUMBER_OF_COMPONENTS) THEN
                        LOCAL_ERROR="Inconsistent dependent variable number of components. Dependent variable index "// &
                          & TRIM(NUMBER_TO_VSTRING(variable_idx,"*",ERR,ERROR))//" has "// &
                          & TRIM(NUMBER_TO_VSTRING(FIELD_VARIABLE%NUMBER_OF_COMPONENTS,"*",ERR,ERROR))// &
                          & " components and dependent variable index 1 has "// &
                          & TRIM(NUMBER_TO_VSTRING(NUMBER_OF_COMPONENTS,"*",ERR,ERROR))//"."
                        CALL FLAG_ERROR(LOCAL_ERROR,ERR,ERROR,*999)
                      ENDIF
                    ELSE
                      LOCAL_ERROR="The interface condition field variables is not associated for variable index "// &
                        & TRIM(NUMBER_TO_VSTRING(variable_idx,"*",ERR,ERROR))
                      CALL FLAG_ERROR(LOCAL_ERROR,ERR,ERROR,*999)
                    ENDIF
                  ENDDO !variable_idx                  
                ELSE
                  CALL FLAG_ERROR("Interface field variable is not associated.",ERR,ERROR,*999)
                ENDIF
              CASE(INTERFACE_CONDITION_FIELD_NORMAL_CONTINUITY_OPERATOR)
                CALL FLAG_ERROR("Not implemented.",ERR,ERROR,*999)
              CASE(INTERFACE_CONDITION_SOLID_FLUID_OPERATOR)
                CALL FLAG_ERROR("Not implemented.",ERR,ERROR,*999)
              CASE(INTERFACE_CONDITION_SOLID_FLUID_NORMAL_OPERATOR)
                CALL FLAG_ERROR("Not implemented.",ERR,ERROR,*999)
              CASE DEFAULT
                LOCAL_ERROR="The interface condition operator of "// &
                  & TRIM(NUMBER_TO_VSTRING(INTERFACE_CONDITION%OPERATOR,"*",ERR,ERROR))//" is invalid."
                CALL FLAG_ERROR(LOCAL_ERROR,ERR,ERROR,*999)
              END SELECT
              !Reorder the dependent variables based on mesh index order
              ALLOCATE(NEW_FIELD_VARIABLES(INTERFACE_DEPENDENT%NUMBER_OF_DEPENDENT_VARIABLES),STAT=ERR)
              IF(ERR/=0) CALL FLAG_ERROR("Could not allocate new field variables.",ERR,ERROR,*999)
              ALLOCATE(NEW_VARIABLE_MESH_INDICES(INTERFACE_DEPENDENT%NUMBER_OF_DEPENDENT_VARIABLES),STAT=ERR)
              IF(ERR/=0) CALL FLAG_ERROR("Could not allocate new variable mesh indices.",ERR,ERROR,*999)
              NEW_VARIABLE_MESH_INDICES=0
              mesh_idx_count=0
              DO mesh_idx=1,INTERFACE%NUMBER_OF_COUPLED_MESHES
                DO variable_idx=1,INTERFACE_DEPENDENT%NUMBER_OF_DEPENDENT_VARIABLES
                  IF(INTERFACE_DEPENDENT%VARIABLE_MESH_INDICES(variable_idx)==mesh_idx) THEN
                    mesh_idx_count=mesh_idx_count+1
                    NEW_FIELD_VARIABLES(mesh_idx_count)%PTR=>INTERFACE_DEPENDENT%FIELD_VARIABLES(variable_idx)%PTR
                    NEW_VARIABLE_MESH_INDICES(mesh_idx_count)=mesh_idx
                  ENDIF
                ENDDO !variable_idx
              ENDDO !mesh_idx
              IF(mesh_idx_count/=INTERFACE_DEPENDENT%NUMBER_OF_DEPENDENT_VARIABLES) &
                & CALL FLAG_ERROR("Invalid dependent variable mesh index setup.",ERR,ERROR,*999)
              IF(ASSOCIATED(INTERFACE_DEPENDENT%FIELD_VARIABLES)) DEALLOCATE(INTERFACE_DEPENDENT%FIELD_VARIABLES)
              IF(ASSOCIATED(INTERFACE_DEPENDENT%VARIABLE_MESH_INDICES)) DEALLOCATE(INTERFACE_DEPENDENT%VARIABLE_MESH_INDICES)
              INTERFACE_DEPENDENT%FIELD_VARIABLES=>NEW_FIELD_VARIABLES
              INTERFACE_DEPENDENT%VARIABLE_MESH_INDICES=>NEW_VARIABLE_MESH_INDICES
            ELSE
              CALL FLAG_ERROR("Interface condition dependent is not associated.",ERR,ERROR,*999)
            ENDIF
          CASE(INTERFACE_CONDITION_AUGMENTED_LAGRANGE_METHOD)
            CALL FLAG_ERROR("Not implemented.",ERR,ERROR,*999)
          CASE(INTERFACE_CONDITION_PENALTY_METHOD)
            CALL FLAG_ERROR("Not implemented.",ERR,ERROR,*999)
          CASE(INTERFACE_CONDITION_POINT_TO_POINT_METHOD)
            CALL FLAG_ERROR("Not implemented.",ERR,ERROR,*999)
          CASE DEFAULT
            LOCAL_ERROR="The interface condition method of "//TRIM(NUMBER_TO_VSTRING(INTERFACE_CONDITION%METHOD,"*",ERR,ERROR))// &
              & " is invalid."
            CALL FLAG_ERROR(LOCAL_ERROR,ERR,ERROR,*999)
          END SELECT
          !Finish the interface condition creation
          INTERFACE_CONDITION%INTERFACE_CONDITION_FINISHED=.TRUE.
        ELSE
          CALL FLAG_ERROR("Interface condition interface is not associated.",ERR,ERROR,*999)
        ENDIF
      ENDIF
    ELSE
      CALL FLAG_ERROR("Interface condition is not associated.",ERR,ERROR,*999)
    ENDIF
       
    CALL EXITS("INTERFACE_CONDITION_CREATE_FINISH")
    RETURN
999 IF(ASSOCIATED(NEW_FIELD_VARIABLES)) DEALLOCATE(NEW_FIELD_VARIABLES)
    IF(ASSOCIATED(NEW_VARIABLE_MESH_INDICES)) DEALLOCATE(NEW_VARIABLE_MESH_INDICES)
    CALL ERRORS("INTERFACE_CONDITION_CREATE_FINISH",ERR,ERROR)    
    CALL EXITS("INTERFACE_CONDITION_CREATE_FINISH")
    RETURN 1
   
  END SUBROUTINE INTERFACE_CONDITION_CREATE_FINISH
        
  !
  !================================================================================================================================
  !

  !>Starts the process of creating an interface condition on an interface. \see OPENCMISS::CMISSInterfaceConditionCreateStart
  SUBROUTINE INTERFACE_CONDITION_CREATE_START(USER_NUMBER,INTERFACE,GEOMETRIC_FIELD,INTERFACE_CONDITION,ERR,ERROR,*)

    !Argument variables
    INTEGER(INTG), INTENT(IN) :: USER_NUMBER !<The user number of the interface condition
    TYPE(INTERFACE_TYPE), POINTER :: INTERFACE !<A pointer to the interface to create the interface condition on
    TYPE(FIELD_TYPE), POINTER :: GEOMETRIC_FIELD !<A pointer to the geometric field for the interface condition.
    TYPE(INTERFACE_CONDITION_TYPE), POINTER :: INTERFACE_CONDITION !<On return, a pointer to the interface condition. Must not be associated on entry.
    INTEGER(INTG), INTENT(OUT) :: ERR !<The error code
    TYPE(VARYING_STRING), INTENT(OUT) :: ERROR !<The error string
    !Local Variables
    INTEGER(INTG) :: DUMMY_ERR,interface_conditions_idx
    TYPE(INTERFACE_TYPE), POINTER :: GEOMETRIC_INTERFACE
    TYPE(INTERFACE_CONDITION_TYPE), POINTER :: NEW_INTERFACE_CONDITION
    TYPE(INTERFACE_CONDITION_PTR_TYPE), POINTER :: NEW_INTERFACE_CONDITIONS(:)
    TYPE(REGION_TYPE), POINTER :: GEOMETRIC_REGION,GEOMETRIC_INTERFACE_PARENT_REGION,INTERFACE_PARENT_REGION
    TYPE(VARYING_STRING) :: DUMMY_ERROR,LOCAL_ERROR
 
    NULLIFY(NEW_INTERFACE_CONDITION)
    NULLIFY(NEW_INTERFACE_CONDITIONS)

    CALL ENTERS("INTERFACE_CONDITION_CREATE_START",ERR,ERROR,*997)

    IF(ASSOCIATED(INTERFACE)) THEN
      IF(ASSOCIATED(INTERFACE%INTERFACE_CONDITIONS)) THEN
        CALL INTERFACE_CONDITION_USER_NUMBER_FIND(USER_NUMBER,INTERFACE,NEW_INTERFACE_CONDITION,ERR,ERROR,*997)
        IF(ASSOCIATED(NEW_INTERFACE_CONDITION)) THEN
          LOCAL_ERROR="Interface condition user number "//TRIM(NUMBER_TO_VSTRING(USER_NUMBER,"*",ERR,ERROR))// &
            & " has already been created on interface number "//TRIM(NUMBER_TO_VSTRING(INTERFACE%USER_NUMBER,"*",ERR,ERROR))//"."
          CALL FLAG_ERROR(LOCAL_ERROR,ERR,ERROR,*997)
        ELSE
          IF(ASSOCIATED(GEOMETRIC_FIELD)) THEN
            IF(GEOMETRIC_FIELD%FIELD_FINISHED) THEN
              !Check the geometric field is defined on the interface
              GEOMETRIC_INTERFACE=>GEOMETRIC_FIELD%INTERFACE
              IF(ASSOCIATED(GEOMETRIC_INTERFACE)) THEN
                IF(ASSOCIATED(GEOMETRIC_INTERFACE,INTERFACE)) THEN
                  NULLIFY(NEW_INTERFACE_CONDITION)
                  !Initialise the new interface condition
                  CALL INTERFACE_CONDITION_INITIALISE(NEW_INTERFACE_CONDITION,ERR,ERROR,*999)
                  !Set default interface condition values
                  NEW_INTERFACE_CONDITION%USER_NUMBER=USER_NUMBER
                  NEW_INTERFACE_CONDITION%GLOBAL_NUMBER=INTERFACE%INTERFACE_CONDITIONS%NUMBER_OF_INTERFACE_CONDITIONS+1
                  NEW_INTERFACE_CONDITION%INTERFACE_CONDITIONS=>INTERFACE%INTERFACE_CONDITIONS
                  NEW_INTERFACE_CONDITION%INTERFACE=>INTERFACE
                  !Default attributes
                  NEW_INTERFACE_CONDITION%GEOMETRY%GEOMETRIC_FIELD=>GEOMETRIC_FIELD
                  NEW_INTERFACE_CONDITION%METHOD=INTERFACE_CONDITION_LAGRANGE_MULTIPLIERS_METHOD
                  NEW_INTERFACE_CONDITION%OPERATOR=INTERFACE_CONDITION_FIELD_CONTINUITY_OPERATOR
                  IF(ASSOCIATED(INTERFACE%pointsConnectivity)) THEN
                    NEW_INTERFACE_CONDITION%integrationType=INTERFACE_CONDITION_DATA_POINTS_INTEGRATION
                  ELSE
                    NEW_INTERFACE_CONDITION%integrationType=INTERFACE_CONDITION_GAUSS_INTEGRATION
                  ENDIF
                  CALL INTERFACE_CONDITION_DEPENDENT_INITIALISE(NEW_INTERFACE_CONDITION,ERR,ERROR,*999)
                  !Add new interface condition into list of interface conditions in the interface
                  ALLOCATE(NEW_INTERFACE_CONDITIONS(INTERFACE%INTERFACE_CONDITIONS%NUMBER_OF_INTERFACE_CONDITIONS+1),STAT=ERR)
                  IF(ERR/=0) CALL FLAG_ERROR("Could not allocate new interface conditions.",ERR,ERROR,*999)
                  DO interface_conditions_idx=1,INTERFACE%INTERFACE_CONDITIONS%NUMBER_OF_INTERFACE_CONDITIONS
                    NEW_INTERFACE_CONDITIONS(interface_conditions_idx)%PTR=>INTERFACE%INTERFACE_CONDITIONS% &
                      & INTERFACE_CONDITIONS(interface_conditions_idx)%PTR
                  ENDDO !interface_conditions_idx
                  NEW_INTERFACE_CONDITIONS(INTERFACE%INTERFACE_CONDITIONS%NUMBER_OF_INTERFACE_CONDITIONS+1)%PTR=> &
                    & NEW_INTERFACE_CONDITION
                  IF(ASSOCIATED(INTERFACE%INTERFACE_CONDITIONS%INTERFACE_CONDITIONS)) DEALLOCATE(INTERFACE%INTERFACE_CONDITIONS% &
                    & INTERFACE_CONDITIONS)
                  INTERFACE%INTERFACE_CONDITIONS%INTERFACE_CONDITIONS=>NEW_INTERFACE_CONDITIONS
                  INTERFACE%INTERFACE_CONDITIONS%NUMBER_OF_INTERFACE_CONDITIONS=INTERFACE%INTERFACE_CONDITIONS% &
                    NUMBER_OF_INTERFACE_CONDITIONS+1
                  !Return the pointer
                  INTERFACE_CONDITION=>NEW_INTERFACE_CONDITION
                ELSE
                  INTERFACE_PARENT_REGION=>INTERFACE%PARENT_REGION
                  IF(ASSOCIATED(INTERFACE_PARENT_REGION)) THEN
                    GEOMETRIC_INTERFACE_PARENT_REGION=>GEOMETRIC_INTERFACE%PARENT_REGION
                    IF(ASSOCIATED(GEOMETRIC_INTERFACE_PARENT_REGION)) THEN
                      LOCAL_ERROR="Geometric field interface does not match specified interface. "// &
                        "The geometric field was created on interface number "// &
                        & TRIM(NUMBER_TO_VSTRING(GEOMETRIC_INTERFACE%USER_NUMBER,"*",ERR,ERROR))// &
                        & " of parent region number "// &
                        & TRIM(NUMBER_TO_VSTRING(GEOMETRIC_INTERFACE_PARENT_REGION%USER_NUMBER,"*",ERR,ERROR))// &
                        & " and the specified interface was created as number "// &
                        & TRIM(NUMBER_TO_VSTRING(INTERFACE%USER_NUMBER,"*",ERR,ERROR))//" on parent region number "// &
                        & TRIM(NUMBER_TO_VSTRING(INTERFACE_PARENT_REGION%USER_NUMBER,"*",ERR,ERROR))//"."
                      CALL FLAG_ERROR(LOCAL_ERROR,ERR,ERROR,*999)
                    ELSE
                      CALL FLAG_ERROR("Geometric interface parent region is not associated.",ERR,ERROR,*999)
                    ENDIF
                  ELSE
                    CALL FLAG_ERROR("Interface parent region is not associated.",ERR,ERROR,*999)
                  ENDIF
                ENDIF
              ELSE
                GEOMETRIC_REGION=>GEOMETRIC_FIELD%REGION
                IF(ASSOCIATED(GEOMETRIC_REGION)) THEN
                  LOCAL_ERROR="The geometric field was created on region number "// &
                    & TRIM(NUMBER_TO_VSTRING(GEOMETRIC_REGION%USER_NUMBER,"*",ERR,ERROR))// &
                    & " and not on the specified interface."
                  CALL FLAG_ERROR(LOCAL_ERROR,ERR,ERROR,*999)
                ELSE
                  CALL FLAG_ERROR("The geometric field does not have a region or interface created.",ERR,ERROR,*999)
                ENDIF
              ENDIF
            ELSE
              CALL FLAG_ERROR("Geometric field has not been finished.",ERR,ERROR,*999)
            ENDIF
          ELSE
            CALL FLAG_ERROR("Geometric field is not finished.",ERR,ERROR,*999)
          ENDIF
        ENDIF
      ELSE
        LOCAL_ERROR="The interface conditions on interface number "// &
          & TRIM(NUMBER_TO_VSTRING(INTERFACE%USER_NUMBER,"*",ERR,ERROR))//" are not associated."
        CALL FLAG_ERROR(LOCAL_ERROR,ERR,ERROR,*997)
      ENDIF
    ELSE
      CALL FLAG_ERROR("Interface is not associated.",ERR,ERROR,*997)
    ENDIF
    
    CALL EXITS("INTERFACE_CONDITION_CREATE_START")
    RETURN
999 IF(ASSOCIATED(NEW_INTERFACE_CONDITION)) CALL INTERFACE_CONDITION_FINALISE(NEW_INTERFACE_CONDITION,DUMMY_ERR,DUMMY_ERROR,*998)
998 IF(ASSOCIATED(NEW_INTERFACE_CONDITIONS)) DEALLOCATE(NEW_INTERFACE_CONDITIONS)
997 CALL ERRORS("INTERFACE_CONDITION_CREATE_START",ERR,ERROR)
    CALL EXITS("INTERFACE_CONDITION_CREATE_START")
    RETURN 1   
  END SUBROUTINE INTERFACE_CONDITION_CREATE_START
  
  !
  !================================================================================================================================
  !

  !>Finalise the interface condition dependent field information and deallocate all memory.
  SUBROUTINE INTERFACE_CONDITION_DEPENDENT_FINALISE(INTERFACE_DEPENDENT,ERR,ERROR,*)

    !Argument variables
    TYPE(INTERFACE_DEPENDENT_TYPE), POINTER :: INTERFACE_DEPENDENT !<A pointer to the interface condition dependent field information to finalise.
    INTEGER(INTG), INTENT(OUT) :: ERR !<The error code
    TYPE(VARYING_STRING), INTENT(OUT) :: ERROR !<The error string
    !Local Variables

    CALL ENTERS("INTERFACE_CONDITION_DEPENDENT_FINALISE",ERR,ERROR,*999)

    IF(ASSOCIATED(INTERFACE_DEPENDENT)) THEN
      IF(ASSOCIATED(INTERFACE_DEPENDENT%EQUATIONS_SETS)) DEALLOCATE(INTERFACE_DEPENDENT%EQUATIONS_SETS)
      IF(ASSOCIATED(INTERFACE_DEPENDENT%FIELD_VARIABLES)) DEALLOCATE(INTERFACE_DEPENDENT%FIELD_VARIABLES)
      IF(ASSOCIATED(INTERFACE_DEPENDENT%VARIABLE_MESH_INDICES)) DEALLOCATE(INTERFACE_DEPENDENT%VARIABLE_MESH_INDICES)
      DEALLOCATE(INTERFACE_DEPENDENT)
    ENDIF
       
    CALL EXITS("INTERFACE_CONDITION_DEPENDENT_FINALISE")
    RETURN
999 CALL ERRORS("INTERFACE_CONDITION_DEPENDENT_FINALISE",ERR,ERROR)
    CALL EXITS("INTERFACE_CONDITION_DEPENDENT_FINALISE")
    RETURN 1
  END SUBROUTINE INTERFACE_CONDITION_DEPENDENT_FINALISE

  !
  !================================================================================================================================
  !

  !>Initialises an interface condition dependent field information.
  SUBROUTINE INTERFACE_CONDITION_DEPENDENT_INITIALISE(INTERFACE_CONDITION,ERR,ERROR,*)

    !Argument variables
    TYPE(INTERFACE_CONDITION_TYPE), POINTER :: INTERFACE_CONDITION !<The pointer to the interface condition to initialise to initialise the dependent field information for.
    INTEGER(INTG), INTENT(OUT) :: ERR !<The error code
    TYPE(VARYING_STRING), INTENT(OUT) :: ERROR !<The error string
    !Local Variables
    INTEGER(INTG) :: DUMMY_ERR
    TYPE(VARYING_STRING) :: DUMMY_ERROR
 
    CALL ENTERS("INTERFACE_CONDITION_DEPENDENT_INITIALISE",ERR,ERROR,*998)

    IF(ASSOCIATED(INTERFACE_CONDITION)) THEN
      IF(ASSOCIATED(INTERFACE_CONDITION%DEPENDENT)) THEN
        CALL FLAG_ERROR("Interface condition dependent is already associated.",ERR,ERROR,*999)
      ELSE
        ALLOCATE(INTERFACE_CONDITION%DEPENDENT,STAT=ERR)
        IF(ERR/=0) CALL FLAG_ERROR("Could not allocate interface condition dependent.",ERR,ERROR,*999)
        INTERFACE_CONDITION%DEPENDENT%INTERFACE_CONDITION=>INTERFACE_CONDITION
        INTERFACE_CONDITION%DEPENDENT%NUMBER_OF_DEPENDENT_VARIABLES=0
        NULLIFY(INTERFACE_CONDITION%DEPENDENT%EQUATIONS_SETS)
        NULLIFY(INTERFACE_CONDITION%DEPENDENT%FIELD_VARIABLES)
        NULLIFY(INTERFACE_CONDITION%DEPENDENT%VARIABLE_MESH_INDICES)
      ENDIF
    ELSE
      CALL FLAG_ERROR("Interface condition is not associated.",ERR,ERROR,*999)
    ENDIF
       
    CALL EXITS("INTERFACE_CONDITION_DEPENDENT_INITIALISE")
    RETURN
999 CALL INTERFACE_CONDITION_DEPENDENT_FINALISE(INTERFACE_CONDITION%DEPENDENT,DUMMY_ERR,DUMMY_ERROR,*998)
998 CALL ERRORS("INTERFACE_CONDITION_DEPENDENT_INITIALISE",ERR,ERROR)
    CALL EXITS("INTERFACE_CONDITION_DEPENDENT_INITIALISE")
    RETURN 1
  END SUBROUTINE INTERFACE_CONDITION_DEPENDENT_INITIALISE

  !
  !================================================================================================================================
  !

  !>Adds an equations set to an interface condition. \see OPENCMISS::CMISSInterfaceConditionEquationsSetAdd
  SUBROUTINE INTERFACE_CONDITION_DEPENDENT_VARIABLE_ADD(INTERFACE_CONDITION,MESH_INDEX,EQUATIONS_SET,VARIABLE_TYPE,ERR,ERROR,*)

    !Argument variables
    TYPE(INTERFACE_CONDITION_TYPE), POINTER :: INTERFACE_CONDITION !<A pointer to the interface condition to add the dependent variable to
    INTEGER(INTG), INTENT(IN) :: MESH_INDEX !<The mesh index in the interface conditions interface that the dependent variable corresponds to
    TYPE(EQUATIONS_SET_TYPE), POINTER :: EQUATIONS_SET !<A pointer to the equations set containing the dependent field to add the variable from.
    INTEGER(INTG), INTENT(IN) :: VARIABLE_TYPE !<The variable type of the dependent field to add \see FIELD_ROUTINES_VariableTypes,FIELD_ROUTINES
    INTEGER(INTG), INTENT(OUT) :: ERR !<The error code
    TYPE(VARYING_STRING), INTENT(OUT) :: ERROR !<The error string
    !Local Variables
    INTEGER(INTG) :: variable_idx
    INTEGER(INTG), POINTER :: NEW_VARIABLE_MESH_INDICES(:)
    LOGICAL :: FOUND_MESH_INDEX
    TYPE(DECOMPOSITION_TYPE), POINTER :: DECOMPOSITION
    TYPE(EQUATIONS_SET_PTR_TYPE), POINTER :: NEW_EQUATIONS_SETS(:)
    TYPE(FIELD_TYPE), POINTER :: DEPENDENT_FIELD
    TYPE(FIELD_VARIABLE_TYPE), POINTER :: FIELD_VARIABLE,INTERFACE_VARIABLE
    TYPE(FIELD_VARIABLE_PTR_TYPE), POINTER :: NEW_FIELD_VARIABLES(:)
    TYPE(INTERFACE_TYPE), POINTER :: INTERFACE
    TYPE(INTERFACE_DEPENDENT_TYPE), POINTER :: INTERFACE_DEPENDENT
    TYPE(MESH_TYPE), POINTER :: DEPENDENT_MESH,INTERFACE_MESH
    TYPE(VARYING_STRING) :: LOCAL_ERROR

    CALL ENTERS("INTERFACE_CONDITION_DEPENDENT_VARIABLE_ADD",ERR,ERROR,*999)

    IF(ASSOCIATED(INTERFACE_CONDITION)) THEN
      INTERFACE_DEPENDENT=>INTERFACE_CONDITION%DEPENDENT
      IF(ASSOCIATED(INTERFACE_DEPENDENT)) THEN
        INTERFACE=>INTERFACE_CONDITION%INTERFACE
        IF(ASSOCIATED(INTERFACE)) THEN
          IF(MESH_INDEX>0.AND.MESH_INDEX<=INTERFACE%NUMBER_OF_COUPLED_MESHES) THEN
            IF(ASSOCIATED(EQUATIONS_SET)) THEN
              DEPENDENT_FIELD=>EQUATIONS_SET%DEPENDENT%DEPENDENT_FIELD
              IF(ASSOCIATED(DEPENDENT_FIELD)) THEN
                IF(VARIABLE_TYPE>=1.AND.VARIABLE_TYPE<=FIELD_NUMBER_OF_VARIABLE_TYPES) THEN
                  FIELD_VARIABLE=>DEPENDENT_FIELD%VARIABLE_TYPE_MAP(VARIABLE_TYPE)%PTR
                  IF(ASSOCIATED(FIELD_VARIABLE)) THEN
                    !Check that the field variable hasn't already been added.
                    variable_idx=1
                    NULLIFY(INTERFACE_VARIABLE)
                    DO WHILE(variable_idx<=INTERFACE_DEPENDENT%NUMBER_OF_DEPENDENT_VARIABLES.AND. &
                      & .NOT.ASSOCIATED(INTERFACE_VARIABLE))
                      IF(ASSOCIATED(FIELD_VARIABLE,INTERFACE_DEPENDENT%FIELD_VARIABLES(variable_idx)%PTR)) THEN
                        INTERFACE_VARIABLE=>INTERFACE_DEPENDENT%FIELD_VARIABLES(variable_idx)%PTR
                      ELSE
                        variable_idx=variable_idx+1
                      ENDIF
                    ENDDO
                    IF(ASSOCIATED(INTERFACE_VARIABLE)) THEN
                      !Check if we are dealing with the same mesh index.
                      IF(MESH_INDEX/=INTERFACE_DEPENDENT%VARIABLE_MESH_INDICES(variable_idx)) THEN
                        LOCAL_ERROR="The dependent variable has already been added to the interface condition at "// &
                          & "position index "//TRIM(NUMBER_TO_VSTRING(variable_idx,"*",ERR,ERROR))//"."
                        CALL FLAG_ERROR(LOCAL_ERROR,ERR,ERROR,*999)
                      ENDIF
                    ELSE
                      !Check the dependent variable and the mesh index match.
                      INTERFACE_MESH=>INTERFACE%COUPLED_MESHES(MESH_INDEX)%PTR
                      IF(ASSOCIATED(INTERFACE_MESH)) THEN                    
                        DECOMPOSITION=>DEPENDENT_FIELD%DECOMPOSITION
                        IF(ASSOCIATED(DECOMPOSITION)) THEN
                          DEPENDENT_MESH=>DECOMPOSITION%MESH
                          IF(ASSOCIATED(DEPENDENT_MESH)) THEN
                            IF(ASSOCIATED(INTERFACE_MESH,DEPENDENT_MESH)) THEN
                              !The meshes match. Check if the dependent variable has already been added for the mesh index.
                              FOUND_MESH_INDEX=.FALSE.
                              DO variable_idx=1,INTERFACE_DEPENDENT%NUMBER_OF_DEPENDENT_VARIABLES
                                IF(INTERFACE_DEPENDENT%VARIABLE_MESH_INDICES(variable_idx)==MESH_INDEX) THEN
                                  FOUND_MESH_INDEX=.TRUE.
                                  EXIT
                                ENDIF
                              ENDDO !variable_idx
                              IF(FOUND_MESH_INDEX) THEN
                                !The mesh index has already been added to replace the dependent variable with the specified variable
                                INTERFACE_DEPENDENT%FIELD_VARIABLES(variable_idx)%PTR=>DEPENDENT_FIELD% &
                                  & VARIABLE_TYPE_MAP(VARIABLE_TYPE)%PTR
                              ELSE
                                !The mesh index has not been found so add a new dependent variable.
                                ALLOCATE(NEW_EQUATIONS_SETS(INTERFACE_DEPENDENT%NUMBER_OF_DEPENDENT_VARIABLES+1),STAT=ERR)
                                IF(ERR/=0) CALL FLAG_ERROR("Could not allocate new equations sets.",ERR,ERROR,*999)
                                ALLOCATE(NEW_FIELD_VARIABLES(INTERFACE_DEPENDENT%NUMBER_OF_DEPENDENT_VARIABLES+1),STAT=ERR)
                                IF(ERR/=0) CALL FLAG_ERROR("Could not allocate new field variables.",ERR,ERROR,*999)
                                ALLOCATE(NEW_VARIABLE_MESH_INDICES(INTERFACE_DEPENDENT%NUMBER_OF_DEPENDENT_VARIABLES+1),STAT=ERR)
                                IF(ERR/=0) CALL FLAG_ERROR("Could not allocate new variable mesh indices.",ERR,ERROR,*999)
                                DO variable_idx=1,INTERFACE_DEPENDENT%NUMBER_OF_DEPENDENT_VARIABLES
                                  NEW_EQUATIONS_SETS(variable_idx)%PTR=>INTERFACE_DEPENDENT%EQUATIONS_SETS(variable_idx)%PTR
                                  NEW_FIELD_VARIABLES(variable_idx)%PTR=>INTERFACE_DEPENDENT%FIELD_VARIABLES(variable_idx)%PTR
                                  NEW_VARIABLE_MESH_INDICES(variable_idx)=INTERFACE_DEPENDENT%VARIABLE_MESH_INDICES(variable_idx)
                                ENDDO !variable_idx
                                NEW_EQUATIONS_SETS(INTERFACE_DEPENDENT%NUMBER_OF_DEPENDENT_VARIABLES+1)%PTR=>EQUATIONS_SET
                                NEW_FIELD_VARIABLES(INTERFACE_DEPENDENT%NUMBER_OF_DEPENDENT_VARIABLES+1)%PTR=>DEPENDENT_FIELD% &
                                  & VARIABLE_TYPE_MAP(VARIABLE_TYPE)%PTR
                                NEW_VARIABLE_MESH_INDICES(INTERFACE_DEPENDENT%NUMBER_OF_DEPENDENT_VARIABLES+1)=MESH_INDEX
                                IF(ASSOCIATED(INTERFACE_DEPENDENT%EQUATIONS_SETS)) DEALLOCATE(INTERFACE_DEPENDENT%EQUATIONS_SETS)
                                IF(ASSOCIATED(INTERFACE_DEPENDENT%FIELD_VARIABLES)) DEALLOCATE(INTERFACE_DEPENDENT%FIELD_VARIABLES)
                                IF(ASSOCIATED(INTERFACE_DEPENDENT%VARIABLE_MESH_INDICES)) &
                                  & DEALLOCATE(INTERFACE_DEPENDENT%VARIABLE_MESH_INDICES)
                                INTERFACE_DEPENDENT%EQUATIONS_SETS=>NEW_EQUATIONS_SETS
                                INTERFACE_DEPENDENT%FIELD_VARIABLES=>NEW_FIELD_VARIABLES
                                INTERFACE_DEPENDENT%VARIABLE_MESH_INDICES=>NEW_VARIABLE_MESH_INDICES
                                INTERFACE_DEPENDENT%NUMBER_OF_DEPENDENT_VARIABLES= &
                                  & INTERFACE_DEPENDENT%NUMBER_OF_DEPENDENT_VARIABLES+1
                              ENDIF
                            ELSE
                              CALL FLAG_ERROR("The dependent field mesh does not match the interface mesh.",ERR,ERROR,*999)
                            ENDIF
                          ELSE
                            CALL FLAG_ERROR("The dependent field decomposition mesh is not associated.",ERR,ERROR,*999)
                          ENDIF
                        ELSE
                          CALL FLAG_ERROR("The dependent field decomposition is not associated.",ERR,ERROR,*999)
                        ENDIF
                      ELSE
                        LOCAL_ERROR="The interface mesh for mesh index "//TRIM(NUMBER_TO_VSTRING(MESH_INDEX,"*",ERR,ERROR))// &
                          & " is not associated."
                        CALL FLAG_ERROR(LOCAL_ERROR,ERR,ERROR,*999)
                      ENDIF
                    ENDIF
                  ELSE
                    LOCAL_ERROR="The field variable type of "//TRIM(NUMBER_TO_VSTRING(VARIABLE_TYPE,"*",ERR,ERROR))// &
                      & " has not been created on field number "// &
                      & TRIM(NUMBER_TO_VSTRING(DEPENDENT_FIELD%USER_NUMBER,"*",ERR,ERROR))//"."
                    CALL FLAG_ERROR(LOCAL_ERROR,ERR,ERROR,*999)
                  ENDIF
                ELSE
                  LOCAL_ERROR="The field variable type of "//TRIM(NUMBER_TO_VSTRING(VARIABLE_TYPE,"*",ERR,ERROR))// &
                    & " is invalid. The variable type must be between 1 and "// &
                    & TRIM(NUMBER_TO_VSTRING(FIELD_NUMBER_OF_VARIABLE_TYPES,"*",ERR,ERROR))//"."
                  CALL FLAG_ERROR(LOCAL_ERROR,ERR,ERROR,*999)              
                ENDIF
              ELSE
                CALL FLAG_ERROR("Equations set dependent field is not associated.",ERR,ERROR,*999)
              ENDIF
            ELSE
              CALL FLAG_ERROR("Equations set is not associated.",ERR,ERROR,*999)
            ENDIF
          ELSE
            LOCAL_ERROR="The specificed mesh index of "//TRIM(NUMBER_TO_VSTRING(MESH_INDEX,"*",ERR,ERROR))// &
              & " is invalid. The mesh index must be > 0 and <= "// &
              & TRIM(NUMBER_TO_VSTRING(INTERFACE%NUMBER_OF_COUPLED_MESHES,"*",ERR,ERROR))//"."
            CALL FLAG_ERROR(LOCAL_ERROR,ERR,ERROR,*999)
          ENDIF
        ELSE
          CALL FLAG_ERROR("Interface condition interface is not associated.",ERR,ERROR,*999)
        ENDIF
      ELSE
        CALL FLAG_ERROR("Interface condition dependent is not associated.",ERR,ERROR,*999)
      ENDIF
    ELSE
      CALL FLAG_ERROR("Interface conditions is not associated.",ERR,ERROR,*999)
    ENDIF
    
    CALL EXITS("INTERFACE_CONDITION_DEPENDENT_VARIABLE_ADD")
    RETURN
999 CALL ERRORS("INTERFACE_CONDITION_DEPENDENT_VARIABLE_ADD",ERR,ERROR)
    CALL EXITS("INTERFACE_CONDITION_DEPENDENT_VARIABLE_ADD")
    RETURN 1   
  END SUBROUTINE INTERFACE_CONDITION_DEPENDENT_VARIABLE_ADD
  
  !
  !================================================================================================================================
  !

  !>Destroys an interface condition. \see OPENCMISS::CMISSInterfaceConditionDestroy
  SUBROUTINE INTERFACE_CONDITION_DESTROY(INTERFACE_CONDITION,ERR,ERROR,*)

    !Argument variables
    TYPE(INTERFACE_CONDITION_TYPE), POINTER :: INTERFACE_CONDITION !<A pointer to the interface condition to destroy
    INTEGER(INTG), INTENT(OUT) :: ERR !<The error code
    TYPE(VARYING_STRING), INTENT(OUT) :: ERROR !<The error string
    !Local Variables
    INTEGER(INTG) :: interface_condition_idx,interface_condition_position
    TYPE(INTERFACE_CONDITION_PTR_TYPE), POINTER :: NEW_INTERFACE_CONDITIONS(:)
    TYPE(INTERFACE_CONDITIONS_TYPE), POINTER :: INTERFACE_CONDITIONS

    NULLIFY(NEW_INTERFACE_CONDITIONS)

    CALL ENTERS("INTERFACE_CONDITION_DESTROY",ERR,ERROR,*999)

    IF(ASSOCIATED(INTERFACE_CONDITION)) THEN
      INTERFACE_CONDITIONS=>INTERFACE_CONDITION%INTERFACE_CONDITIONS
      IF(ASSOCIATED(INTERFACE_CONDITIONS)) THEN
        interface_condition_position=INTERFACE_CONDITION%GLOBAL_NUMBER

        !Destroy all the interface condition components
        CALL INTERFACE_CONDITION_FINALISE(INTERFACE_CONDITION,ERR,ERROR,*999)
        
        !Remove the interface condition from the list of interface conditions
        IF(INTERFACE_CONDITIONS%NUMBER_OF_INTERFACE_CONDITIONS>1) THEN
          ALLOCATE(NEW_INTERFACE_CONDITIONS(INTERFACE_CONDITIONS%NUMBER_OF_INTERFACE_CONDITIONS-1),STAT=ERR)
          IF(ERR/=0) CALL FLAG_ERROR("Could not allocate new interface conditions.",ERR,ERROR,*999)
          DO interface_condition_idx=1,INTERFACE_CONDITIONS%NUMBER_OF_INTERFACE_CONDITIONS
            IF(interface_condition_idx<interface_condition_position) THEN
              NEW_INTERFACE_CONDITIONS(interface_condition_idx)%PTR=>INTERFACE_CONDITIONS% &
                & INTERFACE_CONDITIONS(interface_condition_idx)%PTR
            ELSE IF(interface_condition_idx>interface_condition_position) THEN
              INTERFACE_CONDITIONS%INTERFACE_CONDITIONS(interface_condition_idx)%PTR%GLOBAL_NUMBER=INTERFACE_CONDITIONS% &
                & INTERFACE_CONDITIONS(interface_condition_idx)%PTR%GLOBAL_NUMBER-1
              NEW_INTERFACE_CONDITIONS(interface_condition_idx-1)%PTR=>INTERFACE_CONDITIONS% &
                & INTERFACE_CONDITIONS(interface_condition_idx)%PTR
            ENDIF
          ENDDO !interface_conditions_idx
          IF(ASSOCIATED(INTERFACE_CONDITIONS%INTERFACE_CONDITIONS)) DEALLOCATE(INTERFACE_CONDITIONS%INTERFACE_CONDITIONS)
          INTERFACE_CONDITIONS%INTERFACE_CONDITIONS=>NEW_INTERFACE_CONDITIONS
          INTERFACE_CONDITIONS%NUMBER_OF_INTERFACE_CONDITIONS=INTERFACE_CONDITIONS%NUMBER_OF_INTERFACE_CONDITIONS-1
        ELSE
          DEALLOCATE(INTERFACE_CONDITIONS%INTERFACE_CONDITIONS)
          INTERFACE_CONDITIONS%NUMBER_OF_INTERFACE_CONDITIONS=0
        ENDIF
        
      ELSE
        CALL FLAG_ERROR("Interface conditions interface conditions is not associated.",ERR,ERROR,*999)
      ENDIF
    ELSE
      CALL FLAG_ERROR("Interface conditions is not associated.",ERR,ERROR,*998)
    ENDIF    

    CALL EXITS("INTERFACE_CONDITIONS_DESTROY")
    RETURN
999 IF(ASSOCIATED(NEW_INTERFACE_CONDITIONS)) DEALLOCATE(NEW_INTERFACE_CONDITIONS)
998 CALL ERRORS("INTERFACE_CONDITION_DESTROY",ERR,ERROR)
    CALL EXITS("INTERFACE_CONDITION_DESTROY")
    RETURN 1   
  END SUBROUTINE INTERFACE_CONDITION_DESTROY
  
  !
  !================================================================================================================================
  !

  !>Finish the creation of interface equations for the interface condition. \see OPENCMISS::CMISSInterfaceConditionEquationsCreateFinish
  SUBROUTINE INTERFACE_CONDITION_EQUATIONS_CREATE_FINISH(INTERFACE_CONDITION,ERR,ERROR,*)

    !Argument variables
    TYPE(INTERFACE_CONDITION_TYPE), POINTER :: INTERFACE_CONDITION !<A pointer to the interface condition to finish the creation of the interface equations for.
    INTEGER(INTG), INTENT(OUT) :: ERR !<The error code
    TYPE(VARYING_STRING), INTENT(OUT) :: ERROR !<The error string
    !Local Variables
    INTEGER(INTG), ALLOCATABLE :: STORAGE_TYPE(:),STRUCTURE_TYPE(:)
    LOGICAL, ALLOCATABLE :: MATRICES_TRANSPOSE(:)
    TYPE(INTERFACE_DEPENDENT_TYPE), POINTER :: INTERFACE_DEPENDENT
    TYPE(INTERFACE_EQUATIONS_TYPE), POINTER :: INTERFACE_EQUATIONS
    TYPE(INTERFACE_MAPPING_TYPE), POINTER :: INTERFACE_MAPPING
    TYPE(INTERFACE_MATRICES_TYPE), POINTER :: INTERFACE_MATRICES
    TYPE(VARYING_STRING) :: LOCAL_ERROR
    
    CALL ENTERS("INTERFACE_CONDITIONS_EQUATIONS_CREATE_FINISH",ERR,ERROR,*999)

    IF(ASSOCIATED(INTERFACE_CONDITION)) THEN
      SELECT CASE(INTERFACE_CONDITION%METHOD)
      CASE(INTERFACE_CONDITION_LAGRANGE_MULTIPLIERS_METHOD)
        !Finish the interface equations creation
        NULLIFY(INTERFACE_EQUATIONS)
        CALL INTERFACE_CONDITION_EQUATIONS_GET(INTERFACE_CONDITION,INTERFACE_EQUATIONS,ERR,ERROR,*999)
        IF(INTERFACE_EQUATIONS%INTERFACE_EQUATIONS_FINISHED) THEN
          CALL FLAG_ERROR("Interface condition equations have already been finished.",ERR,ERROR,*999)
        ELSE
          CALL INTERFACE_EQUATIONS_CREATE_FINISH(INTERFACE_EQUATIONS,ERR,ERROR,*999)
          INTERFACE_DEPENDENT=>INTERFACE_CONDITION%DEPENDENT
          IF(ASSOCIATED(INTERFACE_DEPENDENT)) THEN
            !Create the interface mapping.
            NULLIFY(INTERFACE_MAPPING)
            CALL INTERFACE_MAPPING_CREATE_START(INTERFACE_EQUATIONS,INTERFACE_MAPPING,ERR,ERROR,*999)
            CALL INTERFACE_MAPPING_LAGRANGE_VARIABLE_TYPE_SET(INTERFACE_MAPPING,FIELD_U_VARIABLE_TYPE,ERR,ERROR,*999)
            CALL INTERFACE_MAPPING_MATRICES_NUMBER_SET(INTERFACE_MAPPING,INTERFACE_DEPENDENT%NUMBER_OF_DEPENDENT_VARIABLES, &
              & ERR,ERROR,*999)
            ALLOCATE(MATRICES_TRANSPOSE(INTERFACE_DEPENDENT%NUMBER_OF_DEPENDENT_VARIABLES),STAT=ERR)
            IF(ERR/=0) CALL FLAG_ERROR("Could not allocate matrices transpose.",ERR,ERROR,*999)
            MATRICES_TRANSPOSE=.TRUE.
            CALL INTERFACE_MAPPING_MATRICES_TRANSPOSE_SET(INTERFACE_MAPPING,MATRICES_TRANSPOSE,ERR,ERROR,*999)
            IF(ALLOCATED(MATRICES_TRANSPOSE)) DEALLOCATE(MATRICES_TRANSPOSE)
            CALL INTERFACE_MAPPING_RHS_VARIABLE_TYPE_SET(INTERFACE_MAPPING,FIELD_DELUDELN_VARIABLE_TYPE,ERR,ERROR,*999)
            CALL INTERFACE_MAPPING_CREATE_FINISH(INTERFACE_MAPPING,ERR,ERROR,*999)
            !Create the interface matrices
            NULLIFY(INTERFACE_MATRICES)
            CALL INTERFACE_MATRICES_CREATE_START(INTERFACE_EQUATIONS,INTERFACE_MATRICES,ERR,ERROR,*999)
            ALLOCATE(STORAGE_TYPE(INTERFACE_MATRICES%NUMBER_OF_INTERFACE_MATRICES),STAT=ERR)
            IF(ERR/=0) CALL FLAG_ERROR("Could not allocate storage type.",ERR,ERROR,*999)
            SELECT CASE(INTERFACE_EQUATIONS%SPARSITY_TYPE)
            CASE(INTERFACE_MATRICES_FULL_MATRICES) 
              STORAGE_TYPE=MATRIX_BLOCK_STORAGE_TYPE
              CALL INTERFACE_MATRICES_STORAGE_TYPE_SET(INTERFACE_MATRICES,STORAGE_TYPE,ERR,ERROR,*999)
            CASE(INTERFACE_MATRICES_SPARSE_MATRICES) 
              ALLOCATE(STRUCTURE_TYPE(INTERFACE_MATRICES%NUMBER_OF_INTERFACE_MATRICES),STAT=ERR)
              IF(ERR/=0) CALL FLAG_ERROR("Could not allocate structure type.",ERR,ERROR,*999)
              STORAGE_TYPE=MATRIX_COMPRESSED_ROW_STORAGE_TYPE
              STRUCTURE_TYPE=INTERFACE_MATRIX_FEM_STRUCTURE
              CALL INTERFACE_MATRICES_STORAGE_TYPE_SET(INTERFACE_MATRICES,STORAGE_TYPE,ERR,ERROR,*999)
              CALL INTERFACE_MATRICES_STRUCTURE_TYPE_SET(INTERFACE_MATRICES,STRUCTURE_TYPE,ERR,ERROR,*999)
              IF(ALLOCATED(STRUCTURE_TYPE)) DEALLOCATE(STRUCTURE_TYPE)
            CASE DEFAULT
              LOCAL_ERROR="The interface equations sparsity type of "// &
                & TRIM(NUMBER_TO_VSTRING(INTERFACE_EQUATIONS%SPARSITY_TYPE,"*",ERR,ERROR))//" is invalid."
              CALL FLAG_ERROR(LOCAL_ERROR,ERR,ERROR,*999)
            END SELECT
            IF(ALLOCATED(STORAGE_TYPE)) DEALLOCATE(STORAGE_TYPE)
            CALL INTERFACE_MATRICES_CREATE_FINISH(INTERFACE_MATRICES,ERR,ERROR,*999)
          ELSE
            CALL FLAG_ERROR("Interface condition dependent is not associated.",ERR,ERROR,*999)
          ENDIF
        ENDIF
      CASE(INTERFACE_CONDITION_AUGMENTED_LAGRANGE_METHOD)
        CALL FLAG_ERROR("Not implemented.",ERR,ERROR,*999)
      CASE(INTERFACE_CONDITION_PENALTY_METHOD)
        CALL FLAG_ERROR("Not implemented.",ERR,ERROR,*999)
      CASE(INTERFACE_CONDITION_POINT_TO_POINT_METHOD)
        CALL FLAG_ERROR("Not implemented.",ERR,ERROR,*999)
      CASE DEFAULT
        LOCAL_ERROR="The interface condition method of "//TRIM(NUMBER_TO_VSTRING(INTERFACE_CONDITION%METHOD,"*",ERR,ERROR))// &
          & " is invalid."
        CALL FLAG_ERROR(LOCAL_ERROR,ERR,ERROR,*999)
      END SELECT
    ELSE
      CALL FLAG_ERROR("Interface conditions is not associated.",ERR,ERROR,*999)
    ENDIF
       
    CALL EXITS("INTERFACE_CONDITION_EQUATIONS_CREATE_FINISH")
    RETURN
999 IF(ALLOCATED(MATRICES_TRANSPOSE)) DEALLOCATE(MATRICES_TRANSPOSE)
    IF(ALLOCATED(STORAGE_TYPE)) DEALLOCATE(STORAGE_TYPE)
    IF(ALLOCATED(STRUCTURE_TYPE)) DEALLOCATE(STRUCTURE_TYPE)
    CALL ERRORS("INTERFACE_CONDITION_EQUATIONS_CREATE_FINISH",ERR,ERROR)
    CALL EXITS("INTERFACE_CONDITION_EQUATIONS_CREATE_FINISH")
    RETURN 1
    
  END SUBROUTINE INTERFACE_CONDITION_EQUATIONS_CREATE_FINISH

  !
  !================================================================================================================================
  !

  !>Start the creation of interface equations for the interface condition. \see CMISSInterfaceConditionEquationsCreateStart
  !>Default values set for the INTERFACE_EQUATIONS's attributes are:
  !>- OUTPUT_TYPE: 0 (INTERFACE_EQUATIONS_NO_OUTPUT)
  !>- SPARSITY_TYPE: 1 (INTERFACE_EQUATIONS_SPARSE_MATRICES)
  SUBROUTINE INTERFACE_CONDITION_EQUATIONS_CREATE_START(INTERFACE_CONDITION,INTERFACE_EQUATIONS,ERR,ERROR,*)

    !Argument variables
    TYPE(INTERFACE_CONDITION_TYPE), POINTER :: INTERFACE_CONDITION !<A pointer to the interface condition to create the interface equations for
    TYPE(INTERFACE_EQUATIONS_TYPE), POINTER :: INTERFACE_EQUATIONS !<On exit, a pointer to the created interface equations. Must not be associated on entry.
    INTEGER(INTG), INTENT(OUT) :: ERR !<The error code
    TYPE(VARYING_STRING), INTENT(OUT) :: ERROR !<The error string
    !Local Variables
    INTEGER(INTG) :: variable_idx
    TYPE(INTERFACE_DEPENDENT_TYPE), POINTER :: INTERFACE_DEPENDENT
    TYPE(VARYING_STRING) :: LOCAL_ERROR

    CALL ENTERS("INTERFACE_CONDITION_EQUATIONS_CREATE_START",ERR,ERROR,*999)

    IF(ASSOCIATED(INTERFACE_CONDITION)) THEN
      IF(ASSOCIATED(INTERFACE_EQUATIONS)) THEN
        CALL FLAG_ERROR("Interface equations is already associated.",ERR,ERROR,*999)
      ELSE
        NULLIFY(INTERFACE_EQUATIONS)
        SELECT CASE(INTERFACE_CONDITION%METHOD)
        CASE(INTERFACE_CONDITION_LAGRANGE_MULTIPLIERS_METHOD)
          IF(ASSOCIATED(INTERFACE_CONDITION%LAGRANGE)) THEN
            IF(INTERFACE_CONDITION%LAGRANGE%LAGRANGE_FINISHED) THEN
              INTERFACE_DEPENDENT=>INTERFACE_CONDITION%DEPENDENT
              IF(ASSOCIATED(INTERFACE_DEPENDENT)) THEN
                !Initialise the setup
                CALL INTERFACE_EQUATIONS_CREATE_START(INTERFACE_CONDITION,INTERFACE_EQUATIONS,ERR,ERROR,*999)
                !Set the number of interpolation sets
                CALL INTERFACE_EQUATIONS_INTERFACE_INTERP_SETS_NUMBER_SET(INTERFACE_EQUATIONS,1,1,ERR,ERROR,*999)
                DO variable_idx=1,INTERFACE_DEPENDENT%NUMBER_OF_DEPENDENT_VARIABLES
                  CALL INTERFACE_EQUATIONS_VARIABLE_INTERP_SETS_NUMBER_SET(INTERFACE_EQUATIONS,variable_idx,1,1, &
                    & ERR,ERROR,*999)                
                ENDDO !variable_idx
              ELSE
                CALL FLAG_ERROR("Interface condition dependent is not associated.",ERR,ERROR,*999)
              ENDIF
              !Return the pointer
              INTERFACE_EQUATIONS=>INTERFACE_CONDITION%INTERFACE_EQUATIONS
            ELSE
              CALL FLAG_ERROR("Interface condition Lagrange field has not been finished.",ERR,ERROR,*999)
            ENDIF
          ELSE
            CALL FLAG_ERROR("Interface condition Lagrange is not associated.",ERR,ERROR,*999)
          ENDIF
        CASE(INTERFACE_CONDITION_AUGMENTED_LAGRANGE_METHOD)
          CALL FLAG_ERROR("Not implemented.",ERR,ERROR,*999)
        CASE(INTERFACE_CONDITION_PENALTY_METHOD)
          CALL FLAG_ERROR("Not implemented.",ERR,ERROR,*999)
        CASE(INTERFACE_CONDITION_POINT_TO_POINT_METHOD)
          CALL FLAG_ERROR("Not implemented.",ERR,ERROR,*999)
        CASE DEFAULT
          LOCAL_ERROR="The interface condition method of "//TRIM(NUMBER_TO_VSTRING(INTERFACE_CONDITION%METHOD,"*",ERR,ERROR))// &
            & " is invalid."
          CALL FLAG_ERROR(LOCAL_ERROR,ERR,ERROR,*999)
        END SELECT
      ENDIF
    ELSE
      CALL FLAG_ERROR("Interface condition is not associated.",ERR,ERROR,*999)
    ENDIF
       
    CALL EXITS("INTERFACE_CONDITION_EQUATIONS_CREATE_START")
    RETURN
999 CALL ERRORS("INTERFACE_CONDITION_EQUATIONS_CREATE_START",ERR,ERROR)
    CALL EXITS("INTERFACE_CONDITION_EQUATIONS_CREATE_START")
    RETURN 1
  END SUBROUTINE INTERFACE_CONDITION_EQUATIONS_CREATE_START

  !
  !================================================================================================================================
  !

  !>Destroy the interface equations for an interface condition. \see OPENCMISS::CMISSInterfaceConditionEquationsDestroy
  SUBROUTINE INTERFACE_CONDITION_EQUATIONS_DESTROY(INTERFACE_CONDITION,ERR,ERROR,*)

    !Argument variables
    TYPE(INTERFACE_CONDITION_TYPE), POINTER :: INTERFACE_CONDITION !<A pointer to the interface conditions to destroy the interface equations for.
    INTEGER(INTG), INTENT(OUT) :: ERR !<The error code
    TYPE(VARYING_STRING), INTENT(OUT) :: ERROR !<The error string
    !Local Variables

    CALL ENTERS("INTERFACE_CONDITION_EQUATIONS_DESTROY",ERR,ERROR,*999)

    IF(ASSOCIATED(INTERFACE_CONDITION)) THEN
      IF(ASSOCIATED(INTERFACE_CONDITION%INTERFACE_EQUATIONS)) THEN        
        CALL INTERFACE_EQUATIONS_DESTROY(INTERFACE_CONDITION%INTERFACE_EQUATIONS,ERR,ERROR,*999)
      ELSE
        CALL FLAG_ERROR("Interface condition interface equations is not associated.",ERR,ERROR,*999)
      ENDIF
    ELSE
      CALL FLAG_ERROR("Interface condition is not associated.",ERR,ERROR,*999)
    ENDIF
       
    CALL EXITS("INTERFACE_CONDITION_EQUATIONS_DESTROY")
    RETURN
999 CALL ERRORS("INTERFACE_CONDITION_EQUATIONS_DESTROY",ERR,ERROR)
    CALL EXITS("INTERFACE_CONDITION_EQUATIONS_DESTROY")
    RETURN 1
  END SUBROUTINE INTERFACE_CONDITION_EQUATIONS_DESTROY

  !
  !================================================================================================================================
  !

  !>Finalise the interface condition and deallocate all memory.
  SUBROUTINE INTERFACE_CONDITION_FINALISE(INTERFACE_CONDITION,ERR,ERROR,*)

    !Argument variables
    TYPE(INTERFACE_CONDITION_TYPE), POINTER :: INTERFACE_CONDITION !<A pointer to the interface condition to finalise.
    INTEGER(INTG), INTENT(OUT) :: ERR !<The error code
    TYPE(VARYING_STRING), INTENT(OUT) :: ERROR !<The error string
    !Local Variables

    CALL ENTERS("INTERFACE_CONDITION_FINALISE",ERR,ERROR,*999)

    IF(ASSOCIATED(INTERFACE_CONDITION)) THEN
      CALL INTERFACE_CONDITION_GEOMETRY_FINALISE(INTERFACE_CONDITION%GEOMETRY,ERR,ERROR,*999)
      CALL INTERFACE_CONDITION_LAGRANGE_FINALISE(INTERFACE_CONDITION%LAGRANGE,ERR,ERROR,*999)
      CALL INTERFACE_CONDITION_DEPENDENT_FINALISE(INTERFACE_CONDITION%DEPENDENT,ERR,ERROR,*999)
      IF(ASSOCIATED(INTERFACE_CONDITION%INTERFACE_EQUATIONS)) &
        & CALL INTERFACE_EQUATIONS_DESTROY(INTERFACE_CONDITION%INTERFACE_EQUATIONS,ERR,ERROR,*999)
      DEALLOCATE(INTERFACE_CONDITION)
    ENDIF
       
    CALL EXITS("INTERFACE_CONDITION_FINALISE")
    RETURN
999 CALL ERRORS("INTERFACE_CONDITION_FINALISE",ERR,ERROR)
    CALL EXITS("INTERFACE_CONDITION_FINALISE")
    RETURN 1
  END SUBROUTINE INTERFACE_CONDITION_FINALISE

!
  !================================================================================================================================
  !

  !>Returns the interface condition integration type 
  SUBROUTINE InterfaceCondition_IntegrationTypeGet(interfaceCondition,interfaceConditionIntegrationType,err,error,*)

    !Argument variables
    TYPE(INTERFACE_CONDITION_TYPE), POINTER :: interfaceCondition !<A pointer to the interface condition to get the operator for
    INTEGER(INTG), INTENT(OUT) :: interfaceConditionIntegrationType !<On return, the interface condition integration type. \see INTERFACE_CONDITIONS_IntegrationType,INTERFACE_CONDITIONS 
    INTEGER(INTG), INTENT(OUT) :: err !<The error code
    TYPE(VARYING_STRING), INTENT(OUT) :: error !<The error string
    !Local Variables

    CALL ENTERS("InterfaceCondition_IntegrationTypeGet",err,error,*999)

    IF(ASSOCIATED(interfaceCondition)) THEN
      IF(interfaceCondition%INTERFACE_CONDITION_FINISHED) THEN
        interfaceConditionIntegrationType=interfaceCondition%integrationType
      ELSE
        CALL FLAG_ERROR("Interface condition has not been finished.",err,error,*999)
      ENDIF
    ELSE
      CALL FLAG_ERROR("Interface condition is not associated.",err,error,*999)
    ENDIF
    
    CALL EXITS("InterfaceCondition_IntegrationTypeGet")
    RETURN
999 CALL ERRORS("InterfaceCondition_IntegrationTypeGet",err,ERROR)
    CALL EXITS("InterfaceCondition_IntegrationTypeGet")
    RETURN 1
  END SUBROUTINE InterfaceCondition_IntegrationTypeGet
  
  !
  !================================================================================================================================
  !

  !>Sets/changes the interface condition integration type 
  SUBROUTINE InterfaceCondition_IntegrationTypeSet(interfaceCondition,interfaceConditionIntegrationType,err,error,*)

    !Argument variables
    TYPE(INTERFACE_CONDITION_TYPE), POINTER :: interfaceCondition !<A pointer to the interface condition to set the operator for
    INTEGER(INTG), INTENT(IN) :: interfaceConditionIntegrationType !<The interface condition integration type to set. \see INTERFACE_CONDITIONS_IntegrationType,INTERFACE_CONDITIONS 
    INTEGER(INTG), INTENT(OUT) :: err !<The error code
    TYPE(VARYING_STRING), INTENT(OUT) :: error !<The error string
    !Local Variables
    TYPE(VARYING_STRING) :: localError

    CALL ENTERS("InterfaceCondition_IntegrationTypeSet",err,error,*999)

    IF(ASSOCIATED(interfaceCondition)) THEN
      IF(interfaceCondition%INTERFACE_CONDITION_FINISHED) THEN
        CALL FLAG_ERROR("Interface condition has been finished.",err,error,*999)
      ELSE
        SELECT CASE(interfaceConditionIntegrationType)
        CASE(INTERFACE_CONDITION_GAUSS_INTEGRATION)
          interfaceCondition%integrationType=INTERFACE_CONDITION_GAUSS_INTEGRATION
        CASE(INTERFACE_CONDITION_DATA_POINTS_INTEGRATION)
          interfaceCondition%integrationType=INTERFACE_CONDITION_DATA_POINTS_INTEGRATION
        CASE DEFAULT
          localError="The specified interface condition operator of "// &
            & TRIM(NUMBER_TO_VSTRING(interfaceConditionIntegrationType,"*",err,ERROR))//" is not valid."
          CALL FLAG_ERROR(localError,err,error,*999)
        END SELECT
      ENDIF
    ELSE
      CALL FLAG_ERROR("Interface condition is not associated.",err,error,*999)
    ENDIF
    
    CALL EXITS("InterfaceCondition_IntegrationTypeSet")
    RETURN
999 CALL ERRORS("InterfaceCondition_IntegrationTypeSet",err,ERROR)
    CALL EXITS("InterfaceCondition_IntegrationTypeSet")
    RETURN 1
  END SUBROUTINE InterfaceCondition_IntegrationTypeSet


  !
  !================================================================================================================================
  !

  !>Finalise the interface condition geometry information and deallocate all memory.
  SUBROUTINE INTERFACE_CONDITION_GEOMETRY_FINALISE(INTERFACE_GEOMETRY,ERR,ERROR,*)

    !Argument variables
    TYPE(INTERFACE_GEOMETRY_TYPE) :: INTERFACE_GEOMETRY !<The interface condition geometry information to finalise.
    INTEGER(INTG), INTENT(OUT) :: ERR !<The error code
    TYPE(VARYING_STRING), INTENT(OUT) :: ERROR !<The error string
    !Local Variables

    CALL ENTERS("INTERFACE_CONDITION_GEOMETRY_FINALISE",ERR,ERROR,*999)

    NULLIFY(INTERFACE_GEOMETRY%INTERFACE_CONDITION)
    NULLIFY(INTERFACE_GEOMETRY%GEOMETRIC_FIELD)
       
    CALL EXITS("INTERFACE_CONDITION_GEOMETRY_FINALISE")
    RETURN
999 CALL ERRORS("INTERFACE_CONDITION_GEOMETRY_FINALISE",ERR,ERROR)
    CALL EXITS("INTERFACE_CONDITION_GEOMETRY_FINALISE")
    RETURN 1
  END SUBROUTINE INTERFACE_CONDITION_GEOMETRY_FINALISE

  !
  !================================================================================================================================
  !

  !>Initialises an interface condition geometry information.
  SUBROUTINE INTERFACE_CONDITION_GEOMETRY_INITIALISE(INTERFACE_CONDITION,ERR,ERROR,*)

    !Argument variables
    TYPE(INTERFACE_CONDITION_TYPE), POINTER :: INTERFACE_CONDITION !<The pointer to the interface condition to initialise to initialise the geometry information for.
    INTEGER(INTG), INTENT(OUT) :: ERR !<The error code
    TYPE(VARYING_STRING), INTENT(OUT) :: ERROR !<The error string
    !Local Variables
    INTEGER(INTG) :: DUMMY_ERR
    TYPE(VARYING_STRING) :: DUMMY_ERROR
 
    CALL ENTERS("INTERFACE_CONDITION_GEOMETRY_INITIALISE",ERR,ERROR,*998)

    IF(ASSOCIATED(INTERFACE_CONDITION)) THEN
      INTERFACE_CONDITION%GEOMETRY%INTERFACE_CONDITION=>INTERFACE_CONDITION
      NULLIFY(INTERFACE_CONDITION%GEOMETRY%GEOMETRIC_FIELD)
    ELSE
      CALL FLAG_ERROR("Interface condition is not associated.",ERR,ERROR,*999)
    ENDIF
       
    CALL EXITS("INTERFACE_CONDITION_GEOMETRY_INITIALISE")
    RETURN
999 CALL INTERFACE_CONDITION_GEOMETRY_FINALISE(INTERFACE_CONDITION%GEOMETRY,DUMMY_ERR,DUMMY_ERROR,*998)
998 CALL ERRORS("INTERFACE_CONDITION_GEOMETRY_INITIALISE",ERR,ERROR)
    CALL EXITS("INTERFACE_CONDITION_GEOMETRY_INITIALISE")
    RETURN 1
  END SUBROUTINE INTERFACE_CONDITION_GEOMETRY_INITIALISE

  !
  !================================================================================================================================
  !

  !>Initialises an interface condition.
  SUBROUTINE INTERFACE_CONDITION_INITIALISE(INTERFACE_CONDITION,ERR,ERROR,*)

    !Argument variables
    TYPE(INTERFACE_CONDITION_TYPE), POINTER :: INTERFACE_CONDITION !<The pointer to the interface condition to initialise. Must not be associated on entry.
    INTEGER(INTG), INTENT(OUT) :: ERR !<The error code
    TYPE(VARYING_STRING), INTENT(OUT) :: ERROR !<The error string
    !Local Variables
    INTEGER(INTG) :: DUMMY_ERR
    TYPE(VARYING_STRING) :: DUMMY_ERROR
 
    CALL ENTERS("INTERFACE_CONDITION_INITIALISE",ERR,ERROR,*998)

    IF(ASSOCIATED(INTERFACE_CONDITION)) THEN
      CALL FLAG_ERROR("Interface condition is already associated.",ERR,ERROR,*998)
    ELSE
      ALLOCATE(INTERFACE_CONDITION,STAT=ERR)
      IF(ERR/=0) CALL FLAG_ERROR("Could not allocate interface condition.",ERR,ERROR,*999)
      INTERFACE_CONDITION%USER_NUMBER=0
      INTERFACE_CONDITION%GLOBAL_NUMBER=0
      INTERFACE_CONDITION%INTERFACE_CONDITION_FINISHED=.FALSE.
      NULLIFY(INTERFACE_CONDITION%INTERFACE_CONDITIONS)
      NULLIFY(INTERFACE_CONDITION%INTERFACE)
      INTERFACE_CONDITION%METHOD=0
      INTERFACE_CONDITION%OPERATOR=0
      NULLIFY(INTERFACE_CONDITION%LAGRANGE)
      NULLIFY(INTERFACE_CONDITION%DEPENDENT)
      NULLIFY(INTERFACE_CONDITION%INTERFACE_EQUATIONS)
      CALL INTERFACE_CONDITION_GEOMETRY_INITIALISE(INTERFACE_CONDITION,ERR,ERROR,*999)
    ENDIF
       
    CALL EXITS("INTERFACE_CONDITION_INITIALISE")
    RETURN
999 CALL INTERFACE_CONDITION_FINALISE(INTERFACE_CONDITION,DUMMY_ERR,DUMMY_ERROR,*998)
998 CALL ERRORS("INTERFACE_CONDITION_INITIALISE",ERR,ERROR)
    CALL EXITS("INTERFACE_CONDITION_INITIALISE")
    RETURN 1
  END SUBROUTINE INTERFACE_CONDITION_INITIALISE

  !
  !================================================================================================================================
  !

  !>Finishes the process of creating an interface condition. \see OPENCMISS::CMISSInterfaceConditionLagrangeConditionCreateFinish
  SUBROUTINE INTERFACE_CONDITION_LAGRANGE_FIELD_CREATE_FINISH(INTERFACE_CONDITION,ERR,ERROR,*)

    !Argument variables
    TYPE(INTERFACE_CONDITION_TYPE), POINTER :: INTERFACE_CONDITION !<A pointer to the interface condition to finish creating the Lagrange field for
    INTEGER(INTG), INTENT(OUT) :: ERR !<The error code
    TYPE(VARYING_STRING), INTENT(OUT) :: ERROR !<The error string
    !Local Variables
    
    CALL ENTERS("INTERFACE_CONDITION_LAGRANGE_FIELD_CREATE_FINISH",ERR,ERROR,*999)

    IF(ASSOCIATED(INTERFACE_CONDITION)) THEN
      IF(ASSOCIATED(INTERFACE_CONDITION%LAGRANGE)) THEN
        IF(INTERFACE_CONDITION%LAGRANGE%LAGRANGE_FINISHED) THEN
          CALL FLAG_ERROR("Interface condition Lagrange field has already been finished.",ERR,ERROR,*999)
        ELSE
          !Finish the Lagrange field creation
          IF(INTERFACE_CONDITION%LAGRANGE%LAGRANGE_FIELD_AUTO_CREATED) THEN
            CALL FIELD_CREATE_FINISH(INTERFACE_CONDITION%LAGRANGE%LAGRANGE_FIELD,ERR,ERROR,*999)
          ENDIF
          INTERFACE_CONDITION%LAGRANGE%LAGRANGE_FINISHED=.TRUE.
        ENDIF
      ELSE
        CALL FLAG_ERROR("Interface condition Lagrange is not associated.",ERR,ERROR,*999)
      ENDIF
    ELSE
      CALL FLAG_ERROR("Interface condition is not associated.",ERR,ERROR,*999)
    ENDIF
       
    CALL EXITS("INTERFACE_CONDITION_LAGRANGE_FIELD_CREATE_FINISH")
    RETURN
999 CALL ERRORS("INTERFACE_CONDITION_LAGRANGE_FIELD_CREATE_FINISH",ERR,ERROR)    
    CALL EXITS("INTERFACE_CONDITION_LAGRANGE_FIELD_CREATE_FINISH")
    RETURN 1
   
  END SUBROUTINE INTERFACE_CONDITION_LAGRANGE_FIELD_CREATE_FINISH
        
  !
  !================================================================================================================================
  !

  !>Starts the process of creating the Lagrange multiplyer field for interface condition. \see OPENCMISS::CMISSInterfaceConditionLagrangeFieldCreateStart
  SUBROUTINE INTERFACE_CONDITION_LAGRANGE_FIELD_CREATE_START(INTERFACE_CONDITION,LAGRANGE_FIELD_USER_NUMBER,LAGRANGE_FIELD, &
    & ERR,ERROR,*)

    !Argument variables
    TYPE(INTERFACE_CONDITION_TYPE), POINTER :: INTERFACE_CONDITION !<A pointer to the interface condition to create the Lagrange field on
    INTEGER(INTG), INTENT(IN) :: LAGRANGE_FIELD_USER_NUMBER !<The user specified Lagrange field number
    TYPE(FIELD_TYPE), POINTER :: LAGRANGE_FIELD !<If associated on entry, a pointer to the user created Lagrange field which has the same user number as the specified Lagrange field user number. If not associated on entry, on exit, a pointer to the created Lagrange field for the interface condition.
    INTEGER(INTG), INTENT(OUT) :: ERR !<The error code
    TYPE(VARYING_STRING), INTENT(OUT) :: ERROR !<The error string
    !Local Variables
    INTEGER(INTG) :: component_idx,GEOMETRIC_SCALING_TYPE
    TYPE(DECOMPOSITION_TYPE), POINTER :: GEOMETRIC_DECOMPOSITION
    TYPE(FIELD_TYPE), POINTER :: FIELD
    TYPE(INTERFACE_TYPE), POINTER :: INTERFACE
    TYPE(INTERFACE_DEPENDENT_TYPE), POINTER :: INTERFACE_DEPENDENT
    TYPE(REGION_TYPE), POINTER :: INTERFACE_REGION,LAGRANGE_FIELD_REGION
    TYPE(VARYING_STRING) :: LOCAL_ERROR

    CALL ENTERS("INTERFACE_CONDITION_LAGRANGE_FIELD_CREATE_START",ERR,ERROR,*999)

    IF(ASSOCIATED(INTERFACE_CONDITION)) THEN
      IF(ASSOCIATED(INTERFACE_CONDITION%LAGRANGE)) THEN
        CALL FLAG_ERROR("Interface condition Lagrange is already associated.",ERR,ERROR,*999)
      ELSE
        INTERFACE_DEPENDENT=>INTERFACE_CONDITION%DEPENDENT
        IF(ASSOCIATED(INTERFACE_DEPENDENT)) THEN
          INTERFACE=>INTERFACE_CONDITION%INTERFACE
          IF(ASSOCIATED(INTERFACE)) THEN
            INTERFACE_REGION=>INTERFACE%PARENT_REGION
            IF(ASSOCIATED(INTERFACE_REGION)) THEN
              IF(ASSOCIATED(LAGRANGE_FIELD)) THEN
                !Check the Lagrange field has been finished
                IF(LAGRANGE_FIELD%FIELD_FINISHED) THEN
                  !Check the user numbers match
                  IF(LAGRANGE_FIELD_USER_NUMBER/=LAGRANGE_FIELD%USER_NUMBER) THEN
                    LOCAL_ERROR="The specified Lagrange field user number of "// &
                      & TRIM(NUMBER_TO_VSTRING(LAGRANGE_FIELD_USER_NUMBER,"*",ERR,ERROR))// &
                      & " does not match the user number of the specified Lagrange field of "// &
                      & TRIM(NUMBER_TO_VSTRING(LAGRANGE_FIELD%USER_NUMBER,"*",ERR,ERROR))//"."
                    CALL FLAG_ERROR(LOCAL_ERROR,ERR,ERROR,*999)
                  ENDIF
                  LAGRANGE_FIELD_REGION=>LAGRANGE_FIELD%REGION
                  IF(ASSOCIATED(LAGRANGE_FIELD_REGION)) THEN                
                    !Check the field is defined on the same region as the interface
                    IF(LAGRANGE_FIELD_REGION%USER_NUMBER/=INTERFACE_REGION%USER_NUMBER) THEN
                      LOCAL_ERROR="Invalid region setup. The specified Lagrange field has been created on interface number "// &
                        & TRIM(NUMBER_TO_VSTRING(INTERFACE%USER_NUMBER,"*",ERR,ERROR))//" in parent region number "// &
                        & TRIM(NUMBER_TO_VSTRING(LAGRANGE_FIELD_REGION%USER_NUMBER,"*",ERR,ERROR))// &
                        & " and the specified interface has been created in parent region number "// &
                        & TRIM(NUMBER_TO_VSTRING(INTERFACE_REGION%USER_NUMBER,"*",ERR,ERROR))//"."
                      CALL FLAG_ERROR(LOCAL_ERROR,ERR,ERROR,*999)
                    ENDIF
                  ELSE
                    CALL FLAG_ERROR("The Lagrange field region is not associated.",ERR,ERROR,*999)
                  ENDIF
                ELSE
                  CALL FLAG_ERROR("The specified Lagrange field has not been finished.",ERR,ERROR,*999)
                ENDIF
              ELSE
                !Check the user number has not already been used for a field in this region.
                NULLIFY(FIELD)
                CALL FIELD_USER_NUMBER_FIND(LAGRANGE_FIELD_USER_NUMBER,INTERFACE,FIELD,ERR,ERROR,*999)
                IF(ASSOCIATED(FIELD)) THEN
                  LOCAL_ERROR="The specified Lagrange field user number of "// &
                    & TRIM(NUMBER_TO_VSTRING(LAGRANGE_FIELD_USER_NUMBER,"*",ERR,ERROR))// &
                    & " has already been used to create a field on interface number "// &
                    & TRIM(NUMBER_TO_VSTRING(INTERFACE%USER_NUMBER,"*",ERR,ERROR))//"."
                  CALL FLAG_ERROR(LOCAL_ERROR,ERR,ERROR,*999)
                ENDIF
              ENDIF
              CALL INTERFACE_CONDITION_LAGRANGE_INITIALISE(INTERFACE_CONDITION,ERR,ERROR,*999)
              IF(.NOT.ASSOCIATED(LAGRANGE_FIELD)) THEN
                !Create the Lagrange field
                INTERFACE_CONDITION%LAGRANGE%LAGRANGE_FIELD_AUTO_CREATED=.TRUE.
                CALL FIELD_CREATE_START(LAGRANGE_FIELD_USER_NUMBER,INTERFACE_CONDITION%INTERFACE,INTERFACE_CONDITION%LAGRANGE% &
                  & LAGRANGE_FIELD,ERR,ERROR,*999)
                CALL FIELD_LABEL_SET(INTERFACE_CONDITION%LAGRANGE%LAGRANGE_FIELD,"Lagrange Multipliers Field",ERR,ERROR,*999)
                CALL FIELD_TYPE_SET_AND_LOCK(INTERFACE_CONDITION%LAGRANGE%LAGRANGE_FIELD,FIELD_GENERAL_TYPE,ERR,ERROR,*999)
                CALL FIELD_DEPENDENT_TYPE_SET_AND_LOCK(INTERFACE_CONDITION%LAGRANGE%LAGRANGE_FIELD,FIELD_DEPENDENT_TYPE, &
                  & ERR,ERROR,*999)
                NULLIFY(GEOMETRIC_DECOMPOSITION)
                CALL FIELD_MESH_DECOMPOSITION_GET(INTERFACE_CONDITION%GEOMETRY%GEOMETRIC_FIELD,GEOMETRIC_DECOMPOSITION, &
                  & ERR,ERROR,*999)
                CALL FIELD_MESH_DECOMPOSITION_SET_AND_LOCK(INTERFACE_CONDITION%LAGRANGE%LAGRANGE_FIELD,GEOMETRIC_DECOMPOSITION, &
                  & ERR,ERROR,*999)
                CALL FIELD_GEOMETRIC_FIELD_SET_AND_LOCK(INTERFACE_CONDITION%LAGRANGE%LAGRANGE_FIELD,INTERFACE_CONDITION%GEOMETRY% &
                  & GEOMETRIC_FIELD,ERR,ERROR,*999)
                CALL FIELD_NUMBER_OF_VARIABLES_SET_AND_LOCK(INTERFACE_CONDITION%LAGRANGE%LAGRANGE_FIELD,2,ERR,ERROR,*999)
                CALL FIELD_VARIABLE_TYPES_SET_AND_LOCK(INTERFACE_CONDITION%LAGRANGE%LAGRANGE_FIELD,(/FIELD_U_VARIABLE_TYPE, &
                  & FIELD_DELUDELN_VARIABLE_TYPE/),ERR,ERROR,*999)
                CALL FIELD_VARIABLE_LABEL_SET(INTERFACE_CONDITION%LAGRANGE%LAGRANGE_FIELD,FIELD_U_VARIABLE_TYPE,"Lambda", &
                  & ERR,ERROR,*999)
                CALL FIELD_VARIABLE_LABEL_SET(INTERFACE_CONDITION%LAGRANGE%LAGRANGE_FIELD,FIELD_DELUDELN_VARIABLE_TYPE, &
                  & "Lambda RHS",ERR,ERROR,*999)
                CALL FIELD_DIMENSION_SET_AND_LOCK(INTERFACE_CONDITION%LAGRANGE%LAGRANGE_FIELD,FIELD_U_VARIABLE_TYPE, &
                   & FIELD_VECTOR_DIMENSION_TYPE,ERR,ERROR,*999)
                CALL FIELD_DIMENSION_SET_AND_LOCK(INTERFACE_CONDITION%LAGRANGE%LAGRANGE_FIELD,FIELD_DELUDELN_VARIABLE_TYPE, &
                  & FIELD_VECTOR_DIMENSION_TYPE,ERR,ERROR,*999)
                CALL FIELD_DATA_TYPE_SET_AND_LOCK(INTERFACE_CONDITION%LAGRANGE%LAGRANGE_FIELD,FIELD_U_VARIABLE_TYPE, &
                  & FIELD_DP_TYPE,ERR,ERROR,*999)
                CALL FIELD_DATA_TYPE_SET_AND_LOCK(INTERFACE_CONDITION%LAGRANGE%LAGRANGE_FIELD,FIELD_DELUDELN_VARIABLE_TYPE, &
                  & FIELD_DP_TYPE,ERR,ERROR,*999)
                INTERFACE_CONDITION%LAGRANGE%NUMBER_OF_COMPONENTS=INTERFACE_DEPENDENT%FIELD_VARIABLES(1)%PTR%NUMBER_OF_COMPONENTS
                CALL FIELD_NUMBER_OF_COMPONENTS_SET(INTERFACE_CONDITION%LAGRANGE%LAGRANGE_FIELD,FIELD_U_VARIABLE_TYPE, &
                  & INTERFACE_CONDITION%LAGRANGE%NUMBER_OF_COMPONENTS,ERR,ERROR,*999)
                CALL FIELD_NUMBER_OF_COMPONENTS_SET(INTERFACE_CONDITION%LAGRANGE%LAGRANGE_FIELD,FIELD_DELUDELN_VARIABLE_TYPE, &
                  & INTERFACE_CONDITION%LAGRANGE%NUMBER_OF_COMPONENTS,ERR,ERROR,*999)
                DO component_idx=1,INTERFACE_CONDITION%LAGRANGE%NUMBER_OF_COMPONENTS
                  CALL FIELD_COMPONENT_INTERPOLATION_SET(INTERFACE_CONDITION%LAGRANGE%LAGRANGE_FIELD, &
                    & FIELD_U_VARIABLE_TYPE,component_idx,FIELD_NODE_BASED_INTERPOLATION,ERR,ERROR,*999)
                  CALL FIELD_COMPONENT_INTERPOLATION_SET(INTERFACE_CONDITION%LAGRANGE%LAGRANGE_FIELD, &
                    & FIELD_DELUDELN_VARIABLE_TYPE,component_idx,FIELD_NODE_BASED_INTERPOLATION,ERR,ERROR,*999)
                ENDDO !component_idx
                CALL FIELD_SCALING_TYPE_GET(INTERFACE_CONDITION%GEOMETRY%GEOMETRIC_FIELD,GEOMETRIC_SCALING_TYPE, &
                  & ERR,ERROR,*999)
                CALL FIELD_SCALING_TYPE_SET(INTERFACE_CONDITION%LAGRANGE%LAGRANGE_FIELD,GEOMETRIC_SCALING_TYPE, &
                  & ERR,ERROR,*999)
              ELSE
                !Check the Lagrange field
                CALL FLAG_ERROR("Not implemented.",ERR,ERROR,*999)
              ENDIF
              !Set pointers
              IF(INTERFACE_CONDITION%LAGRANGE%LAGRANGE_FIELD_AUTO_CREATED) THEN            
                LAGRANGE_FIELD=>INTERFACE_CONDITION%LAGRANGE%LAGRANGE_FIELD
              ELSE
                INTERFACE_CONDITION%LAGRANGE%LAGRANGE_FIELD=>LAGRANGE_FIELD
              ENDIF
            ELSE
              CALL FLAG_ERROR("The interface parent region is not associated.",ERR,ERROR,*999)
            ENDIF
          ELSE
            CALL FLAG_ERROR("The interface interface conditions is not associated.",ERR,ERROR,*999)
          ENDIF
        ELSE
          CALL FLAG_ERROR("Interface condition dependent is not associated.",ERR,ERROR,*999)
        ENDIF
      ENDIF
    ELSE
      CALL FLAG_ERROR("Interface conditions is not associated.",ERR,ERROR,*999)
    ENDIF
    
    CALL EXITS("INTERFACE_CONDITION_LAGRANGE_FIELD_CREATE_START")
    RETURN
999 CALL ERRORS("INTERFACE_CONDITION_LAGRANGE_FIELD_CREATE_START",ERR,ERROR)
    CALL EXITS("INTERFACE_CONDITION_LAGRANGE_FIELD_CREATE_START")
    RETURN 1   
  END SUBROUTINE INTERFACE_CONDITION_LAGRANGE_FIELD_CREATE_START
  
  !
  !================================================================================================================================
  !

  !>Finalise the interface condition Lagrange information and deallocate all memory.
  SUBROUTINE INTERFACE_CONDITION_LAGRANGE_FINALISE(INTERFACE_LAGRANGE,ERR,ERROR,*)

    !Argument variables
    TYPE(INTERFACE_LAGRANGE_TYPE), POINTER :: INTERFACE_LAGRANGE !<A pointer to the interface condition Lagrange information to finalise.
    INTEGER(INTG), INTENT(OUT) :: ERR !<The error code
    TYPE(VARYING_STRING), INTENT(OUT) :: ERROR !<The error string
    !Local Variables

    CALL ENTERS("INTERFACE_CONDITION_LAGRANGE_FINALISE",ERR,ERROR,*999)

    IF(ASSOCIATED(INTERFACE_LAGRANGE)) THEN
      DEALLOCATE(INTERFACE_LAGRANGE)
    ENDIF
       
    CALL EXITS("INTERFACE_CONDITION_LAGRANGE_FINALISE")
    RETURN
999 CALL ERRORS("INTERFACE_CONDITION_LAGRANGE_FINALISE",ERR,ERROR)
    CALL EXITS("INTERFACE_CONDITION_LAGRANGE_FINALISE")
    RETURN 1
  END SUBROUTINE INTERFACE_CONDITION_LAGRANGE_FINALISE

  !
  !================================================================================================================================
  !

  !>Initialises an interface condition Lagrange information.
  SUBROUTINE INTERFACE_CONDITION_LAGRANGE_INITIALISE(INTERFACE_CONDITION,ERR,ERROR,*)

    !Argument variables
    TYPE(INTERFACE_CONDITION_TYPE), POINTER :: INTERFACE_CONDITION !<The pointer to the interface condition to initialise to initialise the Lagrange information for.
    INTEGER(INTG), INTENT(OUT) :: ERR !<The error code
    TYPE(VARYING_STRING), INTENT(OUT) :: ERROR !<The error string
    !Local Variables
    INTEGER(INTG) :: DUMMY_ERR
    TYPE(VARYING_STRING) :: DUMMY_ERROR
 
    CALL ENTERS("INTERFACE_CONDITION_LAGRANGE_INITIALISE",ERR,ERROR,*998)

    IF(ASSOCIATED(INTERFACE_CONDITION)) THEN
      IF(ASSOCIATED(INTERFACE_CONDITION%LAGRANGE)) THEN
        CALL FLAG_ERROR("Interface condition Lagrange is already associated.",ERR,ERROR,*999)
      ELSE
        ALLOCATE(INTERFACE_CONDITION%LAGRANGE,STAT=ERR)
        IF(ERR/=0) CALL FLAG_ERROR("Could not allocate interface condition Lagrange.",ERR,ERROR,*999)
        INTERFACE_CONDITION%LAGRANGE%INTERFACE_CONDITION=>INTERFACE_CONDITION
        INTERFACE_CONDITION%LAGRANGE%LAGRANGE_FINISHED=.FALSE.
        INTERFACE_CONDITION%LAGRANGE%LAGRANGE_FIELD_AUTO_CREATED=.FALSE.
        NULLIFY(INTERFACE_CONDITION%LAGRANGE%LAGRANGE_FIELD)
        INTERFACE_CONDITION%LAGRANGE%NUMBER_OF_COMPONENTS=0
      ENDIF
    ELSE
      CALL FLAG_ERROR("Interface condition is not associated.",ERR,ERROR,*999)
    ENDIF
       
    CALL EXITS("INTERFACE_CONDITION_LAGRANGE_INITIALISE")
    RETURN
999 CALL INTERFACE_CONDITION_LAGRANGE_FINALISE(INTERFACE_CONDITION%LAGRANGE,DUMMY_ERR,DUMMY_ERROR,*998)
998 CALL ERRORS("INTERFACE_CONDITION_LAGRANGE_INITIALISE",ERR,ERROR)
    CALL EXITS("INTERFACE_CONDITION_LAGRANGE_INITIALISE")
    RETURN 1
  END SUBROUTINE INTERFACE_CONDITION_LAGRANGE_INITIALISE

  !
  !================================================================================================================================
  !

  !>Returns the interface condition method \see OPENCMISS::CMISSInterfaceConditionMethodGet
  SUBROUTINE INTERFACE_CONDITION_METHOD_GET(INTERFACE_CONDITION,INTERFACE_CONDITION_METHOD,ERR,ERROR,*)

    !Argument variables
    TYPE(INTERFACE_CONDITION_TYPE), POINTER :: INTERFACE_CONDITION !<A pointer to the interface condition to get the method for
    INTEGER(INTG), INTENT(OUT) :: INTERFACE_CONDITION_METHOD !<On return, the interface condition method. \see INTERFACE_CONDITIONS_Methods,INTERFACE_CONDITIONS
    INTEGER(INTG), INTENT(OUT) :: ERR !<The error code
    TYPE(VARYING_STRING), INTENT(OUT) :: ERROR !<The error string
    !Local Variables

    CALL ENTERS("INTERFACE_CONDITION_METHOD_GET",ERR,ERROR,*999)

    IF(ASSOCIATED(INTERFACE_CONDITION)) THEN
      IF(INTERFACE_CONDITION%INTERFACE_CONDITION_FINISHED) THEN
        INTERFACE_CONDITION_METHOD=INTERFACE_CONDITION%METHOD
      ELSE
        CALL FLAG_ERROR("Interface condition has not been finished.",ERR,ERROR,*999)
      ENDIF
    ELSE
      CALL FLAG_ERROR("Interface condition is not associated.",ERR,ERROR,*999)
    ENDIF
    
    CALL EXITS("INTERFACE_CONDITION_METHOD_GET")
    RETURN
999 CALL ERRORS("INTERFACE_CONDITION_METHOD_GET",ERR,ERROR)
    CALL EXITS("INTERFACE_CONDITION_METHOD_GET")
    RETURN 1
  END SUBROUTINE INTERFACE_CONDITION_METHOD_GET
  
  !
  !================================================================================================================================
  !

  !>Sets/changes the interface condition method \see OPENCMISS::CMISSInterfaceConditionMethodSet
  SUBROUTINE INTERFACE_CONDITION_METHOD_SET(INTERFACE_CONDITION,INTERFACE_CONDITION_METHOD,ERR,ERROR,*)

    !Argument variables
    TYPE(INTERFACE_CONDITION_TYPE), POINTER :: INTERFACE_CONDITION !<A pointer to the interface condition to set the method for
    INTEGER(INTG), INTENT(IN) :: INTERFACE_CONDITION_METHOD !<The interface condition method to set. \see INTERFACE_CONDITIONS_Methods,INTERFACE_CONDITIONS
    INTEGER(INTG), INTENT(OUT) :: ERR !<The error code
    TYPE(VARYING_STRING), INTENT(OUT) :: ERROR !<The error string
    !Local Variables
    TYPE(VARYING_STRING) :: LOCAL_ERROR

    CALL ENTERS("INTERFACE_CONDITION_METHOD_SET",ERR,ERROR,*999)

    IF(ASSOCIATED(INTERFACE_CONDITION)) THEN
      IF(INTERFACE_CONDITION%INTERFACE_CONDITION_FINISHED) THEN
        CALL FLAG_ERROR("Interface condition has been finished.",ERR,ERROR,*999)
      ELSE
        SELECT CASE(INTERFACE_CONDITION_METHOD)
        CASE(INTERFACE_CONDITION_POINT_TO_POINT_METHOD)
          INTERFACE_CONDITION%METHOD=INTERFACE_CONDITION_POINT_TO_POINT_METHOD
        CASE(INTERFACE_CONDITION_LAGRANGE_MULTIPLIERS_METHOD)
          INTERFACE_CONDITION%METHOD=INTERFACE_CONDITION_LAGRANGE_MULTIPLIERS_METHOD
        CASE(INTERFACE_CONDITION_AUGMENTED_LAGRANGE_METHOD)
          INTERFACE_CONDITION%METHOD=INTERFACE_CONDITION_AUGMENTED_LAGRANGE_METHOD
         CASE(INTERFACE_CONDITION_PENALTY_METHOD)
          INTERFACE_CONDITION%METHOD=INTERFACE_CONDITION_PENALTY_METHOD
       CASE DEFAULT
          LOCAL_ERROR="The specified interface condition method of "// &
            & TRIM(NUMBER_TO_VSTRING(INTERFACE_CONDITION_METHOD,"*",ERR,ERROR))//" is not valid."
          CALL FLAG_ERROR(LOCAL_ERROR,ERR,ERROR,*999)
        END SELECT
      ENDIF
    ELSE
      CALL FLAG_ERROR("Interface condition is not associated.",ERR,ERROR,*999)
    ENDIF
    
    CALL EXITS("INTERFACE_CONDITION_METHOD_SET")
    RETURN
999 CALL ERRORS("INTERFACE_CONDITION_METHOD_SET",ERR,ERROR)
    CALL EXITS("INTERFACE_CONDITION_METHOD_SET")
    RETURN 1
  END SUBROUTINE INTERFACE_CONDITION_METHOD_SET
  
  !
  !================================================================================================================================
  !

  !>Returns the interface condition operator \see OPENCMISS::CMISSInterfaceConditionOperatorGet
  SUBROUTINE INTERFACE_CONDITION_OPERATOR_GET(INTERFACE_CONDITION,INTERFACE_CONDITION_OPERATOR,ERR,ERROR,*)

    !Argument variables
    TYPE(INTERFACE_CONDITION_TYPE), POINTER :: INTERFACE_CONDITION !<A pointer to the interface condition to get the operator for
    INTEGER(INTG), INTENT(OUT) :: INTERFACE_CONDITION_OPERATOR !<On return, the interface condition operator. \see INTERFACE_CONDITIONS_Operators,INTERFACE_CONDITIONS 
    INTEGER(INTG), INTENT(OUT) :: ERR !<The error code
    TYPE(VARYING_STRING), INTENT(OUT) :: ERROR !<The error string
    !Local Variables

    CALL ENTERS("INTERFACE_CONDITION_OPERATOR_GET",ERR,ERROR,*999)

    IF(ASSOCIATED(INTERFACE_CONDITION)) THEN
      IF(INTERFACE_CONDITION%INTERFACE_CONDITION_FINISHED) THEN
        INTERFACE_CONDITION_OPERATOR=INTERFACE_CONDITION%OPERATOR
      ELSE
        CALL FLAG_ERROR("Interface condition has not been finished.",ERR,ERROR,*999)
      ENDIF
    ELSE
      CALL FLAG_ERROR("Interface condition is not associated.",ERR,ERROR,*999)
    ENDIF
    
    CALL EXITS("INTERFACE_CONDITION_OPERATOR_GET")
    RETURN
999 CALL ERRORS("INTERFACE_CONDITION_OPERATOR_GET",ERR,ERROR)
    CALL EXITS("INTERFACE_CONDITION_OPERATOR_GET")
    RETURN 1
  END SUBROUTINE INTERFACE_CONDITION_OPERATOR_GET
  
  !
  !================================================================================================================================
  !

  !>Sets/changes the interface condition operator \see OPENCMISS::CMISSInterfaceConditionOperatorSet
  SUBROUTINE INTERFACE_CONDITION_OPERATOR_SET(INTERFACE_CONDITION,INTERFACE_CONDITION_OPERATOR,ERR,ERROR,*)

    !Argument variables
    TYPE(INTERFACE_CONDITION_TYPE), POINTER :: INTERFACE_CONDITION !<A pointer to the interface condition to set the operator for
    INTEGER(INTG), INTENT(IN) :: INTERFACE_CONDITION_OPERATOR !<The interface condition operator to set. \see INTERFACE_CONDITIONS_Operators,INTERFACE_CONDITIONS 
    INTEGER(INTG), INTENT(OUT) :: ERR !<The error code
    TYPE(VARYING_STRING), INTENT(OUT) :: ERROR !<The error string
    !Local Variables
    TYPE(VARYING_STRING) :: LOCAL_ERROR

    CALL ENTERS("INTERFACE_CONDITION_OPERATOR_SET",ERR,ERROR,*999)

    IF(ASSOCIATED(INTERFACE_CONDITION)) THEN
      IF(INTERFACE_CONDITION%INTERFACE_CONDITION_FINISHED) THEN
        CALL FLAG_ERROR("Interface condition has been finished.",ERR,ERROR,*999)
      ELSE
        SELECT CASE(INTERFACE_CONDITION_OPERATOR)
        CASE(INTERFACE_CONDITION_FIELD_CONTINUITY_OPERATOR)
          INTERFACE_CONDITION%OPERATOR=INTERFACE_CONDITION_FIELD_CONTINUITY_OPERATOR
        CASE(INTERFACE_CONDITION_FIELD_NORMAL_CONTINUITY_OPERATOR)
          INTERFACE_CONDITION%OPERATOR=INTERFACE_CONDITION_FIELD_NORMAL_CONTINUITY_OPERATOR
        CASE(INTERFACE_CONDITION_SOLID_FLUID_OPERATOR)
          INTERFACE_CONDITION%OPERATOR=INTERFACE_CONDITION_SOLID_FLUID_OPERATOR
        CASE(INTERFACE_CONDITION_SOLID_FLUID_NORMAL_OPERATOR)
          INTERFACE_CONDITION%OPERATOR=INTERFACE_CONDITION_SOLID_FLUID_NORMAL_OPERATOR
        CASE DEFAULT
          LOCAL_ERROR="The specified interface condition operator of "// &
            & TRIM(NUMBER_TO_VSTRING(INTERFACE_CONDITION_OPERATOR,"*",ERR,ERROR))//" is not valid."
          CALL FLAG_ERROR(LOCAL_ERROR,ERR,ERROR,*999)
        END SELECT
      ENDIF
    ELSE
      CALL FLAG_ERROR("Interface condition is not associated.",ERR,ERROR,*999)
    ENDIF
    
    CALL EXITS("INTERFACE_CONDITION_OPERATOR_SET")
    RETURN
999 CALL ERRORS("INTERFACE_CONDITION_OPERATOR_SET",ERR,ERROR)
    CALL EXITS("INTERFACE_CONDITION_OPERATOR_SET")
    RETURN 1
  END SUBROUTINE INTERFACE_CONDITION_OPERATOR_SET
  
  !
  !================================================================================================================================
  !

  !>Evaluates the residual for an interface condition.
  SUBROUTINE INTERFACE_CONDITION_RESIDUAL_EVALUATE(INTERFACE_CONDITION,ERR,ERROR,*)

    !Argument variables
    TYPE(INTERFACE_CONDITION_TYPE), POINTER :: INTERFACE_CONDITION !<A pointer to the interface condition to evaluate the residual for
    INTEGER(INTG), INTENT(OUT) :: ERR !<The error code
    TYPE(VARYING_STRING), INTENT(OUT) :: ERROR !<The error string
    !Local Variables
    TYPE(INTERFACE_EQUATIONS_TYPE), POINTER :: INTERFACE_EQUATIONS
    TYPE(VARYING_STRING) :: LOCAL_ERROR

    CALL ENTERS("INTERFACE_CONDITION_RESIDUAL_EVALUATE",ERR,ERROR,*999)

    IF(ASSOCIATED(INTERFACE_CONDITION)) THEN
      INTERFACE_EQUATIONS=>INTERFACE_CONDITION%INTERFACE_EQUATIONS
      IF(ASSOCIATED(INTERFACE_EQUATIONS)) THEN
        IF(INTERFACE_EQUATIONS%INTERFACE_EQUATIONS_FINISHED) THEN
          SELECT CASE(INTERFACE_CONDITION%METHOD)
          CASE(INTERFACE_CONDITION_LAGRANGE_MULTIPLIERS_METHOD)
            CALL INTERFACE_CONDITION_RESIDUAL_EVALUATE_FEM(INTERFACE_CONDITION,ERR,ERROR,*999)
          CASE(INTERFACE_CONDITION_AUGMENTED_LAGRANGE_METHOD)
            CALL FLAG_ERROR("Not implemented.",ERR,ERROR,*999)
          CASE(INTERFACE_CONDITION_PENALTY_METHOD)
            CALL FLAG_ERROR("Not implemented.",ERR,ERROR,*999)
          CASE(INTERFACE_CONDITION_POINT_TO_POINT_METHOD)
            CALL FLAG_ERROR("Not implemented.",ERR,ERROR,*999)
          CASE DEFAULT
            LOCAL_ERROR="The interface condition method of "// &
              & TRIM(NUMBER_TO_VSTRING(INTERFACE_CONDITION%METHOD,"*",ERR,ERROR))// &
              & " is invalid."
            CALL FLAG_ERROR(LOCAL_ERROR,ERR,ERROR,*999)
          END SELECT
        ELSE
          CALL FLAG_ERROR("Interface equations have not been finished.",ERR,ERROR,*999)
        ENDIF
      ELSE
        CALL FLAG_ERROR("Interface condition equations is not associated.",ERR,ERROR,*999)
      ENDIF
    ELSE
      CALL FLAG_ERROR("Interface condition is not associated.",ERR,ERROR,*999)
    ENDIF
    
    CALL EXITS("INTERFACE_CONDITION_RESIDUAL_EVALUATE")
    RETURN
999 CALL ERRORS("INTERFACE_CONDITION_RESIDUAL_EVALUATE",ERR,ERROR)
    CALL EXITS("INTERFACE_CONDITION_RESIDUAL_EVALUATE")
    RETURN 1
    
  END SUBROUTINE INTERFACE_CONDITION_RESIDUAL_EVALUATE

  !
  !================================================================================================================================
  !

  !>Evaluates the residual for an interface condition using the finite element method
  SUBROUTINE INTERFACE_CONDITION_RESIDUAL_EVALUATE_FEM(INTERFACE_CONDITION,ERR,ERROR,*)

    !Argument variables
    TYPE(INTERFACE_CONDITION_TYPE), POINTER :: INTERFACE_CONDITION !<A pointer to the interface condition to evaluate the residual for
    INTEGER(INTG), INTENT(OUT) :: ERR !<The error code
    TYPE(VARYING_STRING), INTENT(OUT) :: ERROR !<The error string
    !Local Variables
    INTEGER(INTG) :: element_idx,ne,NUMBER_OF_TIMES
    REAL(SP) :: ELEMENT_USER_ELAPSED,ELEMENT_SYSTEM_ELAPSED,USER_ELAPSED,USER_TIME1(1),USER_TIME2(1),USER_TIME3(1),USER_TIME4(1), &
      & USER_TIME5(1),USER_TIME6(1),SYSTEM_ELAPSED,SYSTEM_TIME1(1),SYSTEM_TIME2(1),SYSTEM_TIME3(1),SYSTEM_TIME4(1), &
      & SYSTEM_TIME5(1),SYSTEM_TIME6(1)
    TYPE(DOMAIN_MAPPING_TYPE), POINTER :: ELEMENTS_MAPPING
    TYPE(INTERFACE_EQUATIONS_TYPE), POINTER :: INTERFACE_EQUATIONS
    TYPE(INTERFACE_LAGRANGE_TYPE), POINTER :: LAGRANGE
    TYPE(INTERFACE_MATRICES_TYPE), POINTER :: INTERFACE_MATRICES
    TYPE(FIELD_TYPE), POINTER :: LAGRANGE_FIELD
 
    CALL ENTERS("INTERFACE_CONDITION_RESIDUAL_EVALUATE_FEM",ERR,ERROR,*999)

    IF(ASSOCIATED(INTERFACE_CONDITION)) THEN
      LAGRANGE=>INTERFACE_CONDITION%LAGRANGE
      IF(ASSOCIATED(LAGRANGE)) THEN
        LAGRANGE_FIELD=>INTERFACE_CONDITION%LAGRANGE%LAGRANGE_FIELD
        IF(ASSOCIATED(LAGRANGE_FIELD)) THEN
          INTERFACE_EQUATIONS=>INTERFACE_CONDITION%INTERFACE_EQUATIONS
          IF(ASSOCIATED(INTERFACE_EQUATIONS)) THEN
            INTERFACE_MATRICES=>INTERFACE_EQUATIONS%INTERFACE_MATRICES
            IF(ASSOCIATED(INTERFACE_MATRICES)) THEN
              IF(INTERFACE_EQUATIONS%OUTPUT_TYPE>=INTERFACE_EQUATIONS_TIMING_OUTPUT) THEN
                CALL CPU_TIMER(USER_CPU,USER_TIME1,ERR,ERROR,*999)
                CALL CPU_TIMER(SYSTEM_CPU,SYSTEM_TIME1,ERR,ERROR,*999)
              ENDIF
!!Do we need to transfer parameter sets???
              !Initialise the matrices and rhs vector
#ifdef TAUPROF
              CALL TAU_STATIC_PHASE_START("INTERFACE_MATRICES_VALUES_INITIALISE()")
#endif
              CALL INTERFACE_MATRICES_VALUES_INITIALISE(INTERFACE_MATRICES,0.0_DP,ERR,ERROR,*999)
#ifdef TAUPROF
              CALL TAU_STATIC_PHASE_STOP("INTERFACE_MATRICES_VALUES_INITIALISE()")
#endif
              !Assemble the elements
              !Allocate the element matrices 
#ifdef TAUPROF
              CALL TAU_STATIC_PHASE_START("InterfaceMatrices_ElementInitialise()")
#endif
              CALL InterfaceMatrices_ElementInitialise(INTERFACE_MATRICES,ERR,ERROR,*999)
              ELEMENTS_MAPPING=>LAGRANGE_FIELD%DECOMPOSITION%DOMAIN(LAGRANGE_FIELD%DECOMPOSITION%MESH_COMPONENT_NUMBER)%PTR% &
                & MAPPINGS%ELEMENTS
#ifdef TAUPROF
              CALL TAU_STATIC_PHASE_STOP("InterfaceMatrices_ElementInitialise()")
#endif
              !Output timing information if required
              IF(INTERFACE_EQUATIONS%OUTPUT_TYPE>=INTERFACE_EQUATIONS_TIMING_OUTPUT) THEN
                CALL CPU_TIMER(USER_CPU,USER_TIME2,ERR,ERROR,*999)
                CALL CPU_TIMER(SYSTEM_CPU,SYSTEM_TIME2,ERR,ERROR,*999)
                USER_ELAPSED=USER_TIME2(1)-USER_TIME1(1)
                SYSTEM_ELAPSED=SYSTEM_TIME2(1)-SYSTEM_TIME1(1)
                CALL WRITE_STRING_VALUE(GENERAL_OUTPUT_TYPE,"User time for interface setup and initialisation = ",USER_ELAPSED, &
                  & ERR,ERROR,*999)
                CALL WRITE_STRING_VALUE(GENERAL_OUTPUT_TYPE,"System time for interface setup and initialisation = ", &
                  & SYSTEM_ELAPSED,ERR,ERROR,*999)
                ELEMENT_USER_ELAPSED=0.0_SP
                ELEMENT_SYSTEM_ELAPSED=0.0_SP
              ENDIF
              NUMBER_OF_TIMES=0
              !Loop over the internal elements
#ifdef TAUPROF
              CALL TAU_STATIC_PHASE_START("Internal Elements Loop")
#endif
              DO element_idx=ELEMENTS_MAPPING%INTERNAL_START,ELEMENTS_MAPPING%INTERNAL_FINISH
                ne=ELEMENTS_MAPPING%DOMAIN_LIST(element_idx)
                NUMBER_OF_TIMES=NUMBER_OF_TIMES+1
                CALL InterfaceMatrices_ElementCalculate(INTERFACE_MATRICES,ne,ERR,ERROR,*999)
                CALL INTERFACE_CONDITION_FINITE_ELEMENT_CALCULATE(INTERFACE_CONDITION,ne,ERR,ERROR,*999)
                CALL INTERFACE_MATRICES_ELEMENT_ADD(INTERFACE_MATRICES,ERR,ERROR,*999)
              ENDDO !element_idx                  
#ifdef TAUPROF
              CALL TAU_STATIC_PHASE_STOP("Internal Elements Loop")
#endif
              !Output timing information if required
              IF(INTERFACE_EQUATIONS%OUTPUT_TYPE>=INTERFACE_EQUATIONS_TIMING_OUTPUT) THEN
                CALL CPU_TIMER(USER_CPU,USER_TIME3,ERR,ERROR,*999)
                CALL CPU_TIMER(SYSTEM_CPU,SYSTEM_TIME3,ERR,ERROR,*999)
                USER_ELAPSED=USER_TIME3(1)-USER_TIME2(1)
                SYSTEM_ELAPSED=SYSTEM_TIME3(1)-SYSTEM_TIME2(1)
                ELEMENT_USER_ELAPSED=USER_ELAPSED
                ELEMENT_SYSTEM_ELAPSED=SYSTEM_ELAPSED
                CALL WRITE_STRING_VALUE(GENERAL_OUTPUT_TYPE,"User time for internal interface assembly = ",USER_ELAPSED, &
                  & ERR,ERROR,*999)
                CALL WRITE_STRING_VALUE(GENERAL_OUTPUT_TYPE,"System time for internal interface assembly = ",SYSTEM_ELAPSED, &
                  & ERR,ERROR,*999)
              ENDIF
              !Output timing information if required
              IF(INTERFACE_EQUATIONS%OUTPUT_TYPE>=INTERFACE_EQUATIONS_TIMING_OUTPUT) THEN
                CALL CPU_TIMER(USER_CPU,USER_TIME4,ERR,ERROR,*999)
                CALL CPU_TIMER(SYSTEM_CPU,SYSTEM_TIME4,ERR,ERROR,*999)
                USER_ELAPSED=USER_TIME4(1)-USER_TIME3(1)
                SYSTEM_ELAPSED=SYSTEM_TIME4(1)-SYSTEM_TIME3(1)
                CALL WRITE_STRING_VALUE(GENERAL_OUTPUT_TYPE,"User time for parameter transfer completion = ",USER_ELAPSED, &
                  & ERR,ERROR,*999)
                CALL WRITE_STRING_VALUE(GENERAL_OUTPUT_TYPE,"System time for parameter transfer completion = ",SYSTEM_ELAPSED, &
                  & ERR,ERROR,*999)              
              ENDIF
              !Loop over the boundary and ghost elements
#ifdef TAUPROF
              CALL TAU_STATIC_PHASE_START("Boundary and Ghost Elements Loop")
#endif
              DO element_idx=ELEMENTS_MAPPING%BOUNDARY_START,ELEMENTS_MAPPING%GHOST_FINISH
                ne=ELEMENTS_MAPPING%DOMAIN_LIST(element_idx)
                NUMBER_OF_TIMES=NUMBER_OF_TIMES+1
                CALL InterfaceMatrices_ElementCalculate(INTERFACE_MATRICES,ne,ERR,ERROR,*999)
                CALL INTERFACE_CONDITION_FINITE_ELEMENT_CALCULATE(INTERFACE_CONDITION,ne,ERR,ERROR,*999)
                CALL INTERFACE_MATRICES_ELEMENT_ADD(INTERFACE_MATRICES,ERR,ERROR,*999)
              ENDDO !element_idx
#ifdef TAUPROF
              CALL TAU_STATIC_PHASE_STOP("Boundary and Ghost Elements Loop")
#endif
              !Output timing information if required
              IF(INTERFACE_EQUATIONS%OUTPUT_TYPE>=INTERFACE_EQUATIONS_TIMING_OUTPUT) THEN
                CALL CPU_TIMER(USER_CPU,USER_TIME5,ERR,ERROR,*999)
                CALL CPU_TIMER(SYSTEM_CPU,SYSTEM_TIME5,ERR,ERROR,*999)
                USER_ELAPSED=USER_TIME5(1)-USER_TIME4(1)
                SYSTEM_ELAPSED=SYSTEM_TIME5(1)-SYSTEM_TIME4(1)
                ELEMENT_USER_ELAPSED=ELEMENT_USER_ELAPSED+USER_ELAPSED
                ELEMENT_SYSTEM_ELAPSED=ELEMENT_SYSTEM_ELAPSED+USER_ELAPSED
                CALL WRITE_STRING_VALUE(GENERAL_OUTPUT_TYPE,"User time for boundary+ghost interface assembly = ",USER_ELAPSED, &
                  & ERR,ERROR,*999)
                CALL WRITE_STRING_VALUE(GENERAL_OUTPUT_TYPE,"System time for boundary+ghost interface assembly = ", &
                  & SYSTEM_ELAPSED,ERR,ERROR,*999)
                IF(NUMBER_OF_TIMES>0) THEN
                  CALL WRITE_STRING_VALUE(GENERAL_OUTPUT_TYPE,"Average element user time for interface assembly = ", &
                    & ELEMENT_USER_ELAPSED/NUMBER_OF_TIMES,ERR,ERROR,*999)
                  CALL WRITE_STRING_VALUE(GENERAL_OUTPUT_TYPE,"Average element system time for interface assembly = ", &
                    & ELEMENT_SYSTEM_ELAPSED/NUMBER_OF_TIMES,ERR,ERROR,*999)
                ENDIF
              ENDIF
              !Finalise the element matrices
#ifdef TAUPROF
              CALL TAU_STATIC_PHASE_START("INTERFACE_MATRICES_ELEMENT_FINALISE()")
#endif
              CALL INTERFACE_MATRICES_ELEMENT_FINALISE(INTERFACE_MATRICES,ERR,ERROR,*999)
#ifdef TAUPROF
              CALL TAU_STATIC_PHASE_STOP("INTERFACE_MATRICES_ELEMENT_FINALISE()")
#endif
              !Output equations matrices and RHS vector if required
              IF(INTERFACE_EQUATIONS%OUTPUT_TYPE>=INTERFACE_EQUATIONS_MATRIX_OUTPUT) THEN
                CALL INTERFACE_MATRICES_OUTPUT(GENERAL_OUTPUT_TYPE,INTERFACE_MATRICES,ERR,ERROR,*999)
              ENDIF
              !Output timing information if required
              IF(INTERFACE_EQUATIONS%OUTPUT_TYPE>=INTERFACE_EQUATIONS_TIMING_OUTPUT) THEN
                CALL CPU_TIMER(USER_CPU,USER_TIME6,ERR,ERROR,*999)
                CALL CPU_TIMER(SYSTEM_CPU,SYSTEM_TIME6,ERR,ERROR,*999)
                USER_ELAPSED=USER_TIME6(1)-USER_TIME1(1)
                SYSTEM_ELAPSED=SYSTEM_TIME6(1)-SYSTEM_TIME1(1)
                CALL WRITE_STRING(GENERAL_OUTPUT_TYPE,"***",ERR,ERROR,*999)
                CALL WRITE_STRING_VALUE(GENERAL_OUTPUT_TYPE,"Total user time for interface equations assembly = ",USER_ELAPSED, &
                  & ERR,ERROR,*999)
                CALL WRITE_STRING_VALUE(GENERAL_OUTPUT_TYPE,"Total system time for interface equations assembly = ", &
                  & SYSTEM_ELAPSED,ERR,ERROR,*999)
                CALL WRITE_STRING(GENERAL_OUTPUT_TYPE,"***",ERR,ERROR,*999)
              ENDIF
            ELSE
              CALL FLAG_ERROR("Interface matrices is not associated.",ERR,ERROR,*999)
            ENDIF
          ELSE
            CALL FLAG_ERROR("Interface equations is not associated.",ERR,ERROR,*999)
          ENDIF
        ELSE
          CALL FLAG_ERROR("Interface condition Lagrange field is not associated.",ERR,ERROR,*999)
        ENDIF
      ELSE
        CALL FLAG_ERROR("Interface condition Lagrange is not associated",ERR,ERROR,*999)
      ENDIF
    ELSE
      CALL FLAG_ERROR("Interface condition is not associated.",ERR,ERROR,*999)
    ENDIF
       
    CALL EXITS("INTERFACE_CONDITION_RESIDUAL_EVALUATE_FEM")
    RETURN
999 CALL ERRORS("INTERFACE_CONDITION_RESIDUAL_EVALUATE_FEM",ERR,ERROR)
    CALL EXITS("INTERFACE_CONDITION_RESIDUAL_EVALUATE_FEM")
    RETURN 1
    
  END SUBROUTINE INTERFACE_CONDITION_RESIDUAL_EVALUATE_FEM
  
  !
  !================================================================================================================================
  !

  !>Calculates the element stiffness matries for the given element number for a finite element interface equations.
  SUBROUTINE INTERFACE_CONDITION_FINITE_ELEMENT_CALCULATE(INTERFACE_CONDITION,ELEM,ERR,ERROR,*)

    !Argument variables
    TYPE(INTERFACE_CONDITION_TYPE), POINTER :: INTERFACE_CONDITION !<A pointer to the interface condition
    TYPE(INTERFACE_EQUATIONS_TYPE), POINTER :: INTERFACE_EQUATIONS !<A pointer to the interface equations
    INTEGER(INTG), INTENT(IN) :: ELEM !<The element number to calcualte
    INTEGER(INTG), INTENT(OUT) :: ERR !<The error code 
    TYPE(VARYING_STRING), INTENT(OUT) :: ERROR !<The error string
    !Local Variables
    INTEGER(INTG) ng, mh, mhs, ms, nh, nhs, ns, nhc, mhc, dir
    REAL(DP) :: XI(3)
    REAL(DP) :: RWG, PGMSI, PGNSI
    INTEGER(INTG) :: MID
    INTEGER(INTG) :: FVAR_TYPE_RW, FVAR_TYPE_CL
    TYPE(BASIS_TYPE), POINTER :: COLBAS,ROWBAS,GEOMBAS
    TYPE(FIELD_VARIABLE_TYPE), POINTER :: FVAR_RW, FVAR_CL
    TYPE(ELEMENT_MATRIX_TYPE), POINTER :: ELEMENT_MATRIX, EQMAT
    TYPE(INTERFACE_MATRICES_TYPE), POINTER :: INTERFACE_MATRICES
    TYPE(INTERFACE_MATRIX_TYPE), POINTER :: INTERFACE_MATRIX
    TYPE(FIELD_TYPE), POINTER :: ROWVAR, COLVAR, GEOMVAR
    TYPE(QUADRATURE_SCHEME_TYPE), POINTER :: QUADSCHEME, QUADSCHEMECOL, QUADSCHEMEROW
    TYPE(VARYING_STRING) :: LOCAL_ERROR
    
#ifdef TAUPROF
    CALL TAU_STATIC_PHASE_START("INTERFACE_CONDITION_FINITE_ELEMENT_CALCULATE()")
#endif

    CALL ENTERS("INTERFACE_CONDITION_FINITE_ELEMENT_CALCULATE",ERR,ERROR,*999)
    IF(.NOT.ASSOCIATED(INTERFACE_CONDITION)) CALL FLAG_ERROR("Interface condition is not associated.",ERR,ERROR,*999)
    IF(.NOT.ASSOCIATED(INTERFACE_CONDITION%INTERFACE_EQUATIONS)) CALL FLAG_ERROR("Interface equations is not associated." &
      & ,ERR,ERROR,*999)

    INTERFACE_EQUATIONS=>INTERFACE_CONDITION%INTERFACE_EQUATIONS
    SELECT CASE(INTERFACE_CONDITION%METHOD)
    CASE(INTERFACE_CONDITION_POINT_TO_POINT_METHOD)
      CALL FLAG_ERROR("Not implemented.",ERR,ERROR,*999)
    CASE(INTERFACE_CONDITION_LAGRANGE_MULTIPLIERS_METHOD)
      GEOMVAR=>INTERFACE_EQUATIONS%INTERPOLATION%INTERFACE_INTERPOLATION%GEOMETRIC_FIELD
      COLVAR =>INTERFACE_EQUATIONS%INTERPOLATION%INTERFACE_INTERPOLATION%DEPENDENT_FIELD
      FVAR_CL=>INTERFACE_EQUATIONS%INTERFACE_MAPPING%LAGRANGE_VARIABLE
      FVAR_TYPE_CL=FVAR_CL%VARIABLE_TYPE
      DO MID = 1,INTERFACE_CONDITION%INTERFACE%NUMBER_OF_COUPLED_MESHES
        IF (INTERFACE_EQUATIONS%INTERFACE_MATRICES%MATRICES(MID)%PTR%UPDATE_MATRIX) THEN
          ROWVAR=>INTERFACE_EQUATIONS%INTERPOLATION%VARIABLE_INTERPOLATION(MID)%DEPENDENT_FIELD
          EQMAT =>INTERFACE_EQUATIONS%INTERFACE_MATRICES%MATRICES(MID)%PTR%ELEMENT_MATRIX
          FVAR_RW=>INTERFACE_EQUATIONS%INTERFACE_MAPPING%INTERFACE_MATRIX_ROWS_TO_VAR_MAPS(MID)%VARIABLE
          FVAR_TYPE_RW=FVAR_RW%VARIABLE_TYPE
          GEOMBAS=>GEOMVAR%DECOMPOSITION%DOMAIN(GEOMVAR%DECOMPOSITION%MESH_COMPONENT_NUMBER)%PTR% &
             & TOPOLOGY%ELEMENTS%ELEMENTS(ELEM)%BASIS
          INTERFACE_MATRIX=>INTERFACE_EQUATIONS%INTERFACE_MATRICES%MATRICES(MID)%PTR
          CALL FIELD_INTERPOLATION_PARAMETERS_ELEMENT_GET(FIELD_VALUES_SET_TYPE,ELEM,INTERFACE_EQUATIONS%INTERPOLATION% &  
             & INTERFACE_INTERPOLATION%GEOMETRIC_INTERPOLATION(1)%INTERPOLATION_PARAMETERS(FIELD_U_VARIABLE_TYPE)%PTR, &
             & ERR,ERROR,*999)
          QUADSCHEME=>GEOMBAS%QUADRATURE%QUADRATURE_SCHEME_MAP(BASIS_DEFAULT_QUADRATURE_SCHEME)%PTR
          !Loop over gauss points
          DO ng=1,QUADSCHEME%NUMBER_OF_GAUSS
            CALL FIELD_INTERPOLATE_GAUSS(FIRST_PART_DERIV,BASIS_DEFAULT_QUADRATURE_SCHEME,ng,INTERFACE_EQUATIONS%INTERPOLATION% &
              & INTERFACE_INTERPOLATION%GEOMETRIC_INTERPOLATION(1)%INTERPOLATED_POINT(FIELD_U_VARIABLE_TYPE)%PTR, &
              & ERR,ERROR,*999)
            CALL FIELD_INTERPOLATED_POINT_METRICS_CALCULATE(GEOMBAS%NUMBER_OF_XI,INTERFACE_EQUATIONS%INTERPOLATION% &  
              & INTERFACE_INTERPOLATION%GEOMETRIC_INTERPOLATION(1)%INTERPOLATED_POINT_METRICS(FIELD_U_VARIABLE_TYPE)%PTR, &
              & ERR,ERROR,*999)
            RWG=INTERFACE_EQUATIONS%INTERPOLATION%INTERFACE_INTERPOLATION%GEOMETRIC_INTERPOLATION(1)% &
              & INTERPOLATED_POINT_METRICS(FIELD_U_VARIABLE_TYPE)%PTR%JACOBIAN * QUADSCHEME%GAUSS_WEIGHTS(ng)
            dir=SIZE(INTERFACE_CONDITION%INTERFACE%MESH_CONNECTIVITY%ELEMENTS_CONNECTIVITY(ELEM,MID)%XI,1)
            XI(1:dir)=INTERFACE_TRANSFORM_GPT(INTERFACE_CONDITION%INTERFACE%MESH_CONNECTIVITY,ELEM,MID,ng,ERR,ERROR)
            mhs=0
            DO mh=1,FVAR_RW%NUMBER_OF_COMPONENTS
              mhc=FVAR_RW%COMPONENTS(mh)%MESH_COMPONENT_NUMBER
              ROWBAS=>ROWVAR%DECOMPOSITION%DOMAIN(mhc)%PTR%TOPOLOGY%ELEMENTS%ELEMENTS(ELEM)%BASIS
              QUADSCHEMEROW=>ROWBAS%QUADRATURE%QUADRATURE_SCHEME_MAP(BASIS_DEFAULT_QUADRATURE_SCHEME)%PTR
              !Loop over element rows
              DO ms=1,ROWBAS%NUMBER_OF_ELEMENT_PARAMETERS
                mhs=mhs+1; nhs=0; PGMSI=BASIS_EVALUATE_XI(ROWBAS,mhs,NO_PART_DERIV,XI,ERR,ERROR)
                !Loop over element columns
                DO nh=1,FVAR_CL%NUMBER_OF_COMPONENTS
                  nhc=FVAR_CL%COMPONENTS(nh)%MESH_COMPONENT_NUMBER
                  COLBAS=>COLVAR%DECOMPOSITION%DOMAIN(nhc)%PTR%TOPOLOGY%ELEMENTS%ELEMENTS(ELEM)%BASIS
                  QUADSCHEMECOL=>COLBAS%QUADRATURE%QUADRATURE_SCHEME_MAP(BASIS_DEFAULT_QUADRATURE_SCHEME)%PTR
                  DO ns=1,COLBAS%NUMBER_OF_ELEMENT_PARAMETERS
                    nhs=nhs+1; PGNSI=QUADSCHEMECOL%GAUSS_BASIS_FNS(ns,NO_PART_DERIV,ng)
                    INTERFACE_MATRIX%ELEMENT_MATRIX%MATRIX(mhs,nhs)=INTERFACE_MATRIX%ELEMENT_MATRIX%MATRIX(mhs,nhs)+PGNSI*PGMSI*RWG
                  ENDDO !ns
                ENDDO !nh
              ENDDO !ms
            ENDDO !mh
          ENDDO !ng
          !Scale factor adjustment for the Column Variable
          IF(COLVAR%SCALINGS%SCALING_TYPE/=FIELD_NO_SCALING) THEN
            CALL FIELD_INTERPOLATION_PARAMETERS_SCALE_FACTORS_ELEM_GET(ELEM,INTERFACE_EQUATIONS%INTERPOLATION% &  
              & INTERFACE_INTERPOLATION%DEPENDENT_INTERPOLATION(1)%INTERPOLATION_PARAMETERS(FVAR_TYPE_CL)%PTR,ERR,ERROR,*999)
            mhs=0
            DO mh=1,FVAR_RW%NUMBER_OF_COMPONENTS
              !Loop over element rows
              DO ms=1,ROWBAS%NUMBER_OF_ELEMENT_PARAMETERS
                mhs=mhs+1; nhs=0
                !Loop over element columns
                DO nh=1,FVAR_CL%NUMBER_OF_COMPONENTS
                  DO ns=1,COLBAS%NUMBER_OF_ELEMENT_PARAMETERS
                    nhs=nhs+1
!                     INTERFACE_MATRIX%ELEMENT_MATRIX%MATRIX(mhs,nhs)=INTERFACE_MATRIX%ELEMENT_MATRIX%MATRIX(mhs,nhs) * &
!                     & INTERFACE_EQUATIONS%INTERPOLATION%INTERFACE_INTERPOLATION%DEPENDENT_INTERPOLATION(1)% &
!                     & INTERPOLATION_PARAMETERS(FVAR_TYPE_CL)%PTR%SCALE_FACTORS(ms,mh) * INTERFACE_EQUATIONS%INTERPOLATION% &
!                     & INTERFACE_INTERPOLATION%DEPENDENT_INTERPOLATION(1)%INTERPOLATION_PARAMETERS(FVAR_TYPE_CL)%PTR% &
!                     & SCALE_FACTORS(ns,nh)
                  ENDDO !ns
                ENDDO !nh
              ENDDO !ms
            ENDDO !mh
          ENDIF
          !Scale factor adjustment for the Column Variable
          IF(ROWVAR%SCALINGS%SCALING_TYPE/=FIELD_NO_SCALING) THEN
            CALL FIELD_INTERPOLATION_PARAMETERS_SCALE_FACTORS_ELEM_GET(ELEM,INTERFACE_EQUATIONS%INTERPOLATION% &  
              & VARIABLE_INTERPOLATION(MID)%DEPENDENT_INTERPOLATION(1)%INTERPOLATION_PARAMETERS(FVAR_TYPE_RW)%PTR,ERR,ERROR,*999)
            mhs=0
            DO mh=1,FVAR_RW%NUMBER_OF_COMPONENTS
              !Loop over element rows
              DO ms=1,ROWBAS%NUMBER_OF_ELEMENT_PARAMETERS
                mhs=mhs+1; nhs=0
                !Loop over element columns
                DO nh=1,FVAR_CL%NUMBER_OF_COMPONENTS
                  DO ns=1,COLBAS%NUMBER_OF_ELEMENT_PARAMETERS
                    nhs=nhs+1
!                     INTERFACE_MATRIX%ELEMENT_MATRIX%MATRIX(mhs,nhs)=INTERFACE_MATRIX%ELEMENT_MATRIX%MATRIX(mhs,nhs)* &
!                     & INTERFACE_EQUATIONS%INTERPOLATION%VARIABLE_INTERPOLATION(MID)%DEPENDENT_INTERPOLATION(1)% & 
!                     & INTERPOLATION_PARAMETERS(FVAR_TYPE_RW)%PTR%SCALE_FACTORS(ms,mh) * INTERFACE_EQUATIONS%INTERPOLATION% &
!                     & VARIABLE_INTERPOLATION(MID)%DEPENDENT_INTERPOLATION(1)%INTERPOLATION_PARAMETERS(FVAR_TYPE_RW)%PTR% &
!                     & SCALE_FACTORS(ns,nh)
                  ENDDO !ns
                ENDDO !nh
              ENDDO !ms
            ENDDO !mh
          ENDIF
        ENDIF ! UPDATE MATRIX
      ENDDO ! MID
    CASE(INTERFACE_CONDITION_AUGMENTED_LAGRANGE_METHOD)
      CALL FLAG_ERROR("Not implemented.",ERR,ERROR,*999)
    CASE(INTERFACE_CONDITION_PENALTY_METHOD)
      CALL FLAG_ERROR("Not implemented.",ERR,ERROR,*999)
    CASE DEFAULT
      LOCAL_ERROR="Interface condition method "//TRIM(NUMBER_TO_VSTRING(INTERFACE_CONDITION%METHOD,"*",ERR,ERROR))// &
        & " is not valid."
      CALL FLAG_ERROR(LOCAL_ERROR,ERR,ERROR,*999)
    END SELECT

!    IF(INTERFACE_EQUATIONS%OUTPUT_TYPE>=INTERFACE_EQUATIONS_ELEMENT_MATRIX_OUTPUT) THEN
      INTERFACE_MATRICES=>INTERFACE_EQUATIONS%INTERFACE_MATRICES
      IF(ASSOCIATED(INTERFACE_MATRICES)) THEN
        CALL WRITE_STRING(GENERAL_OUTPUT_TYPE,"Finite element interface matrices:",ERR,ERROR,*999)          
        CALL WRITE_STRING_VALUE(GENERAL_OUTPUT_TYPE,"Element number = ",ELEM,ERR,ERROR,*999)
        CALL WRITE_STRING_VALUE(GENERAL_OUTPUT_TYPE,"Number of element matrices = ",INTERFACE_MATRICES% &
          & NUMBER_OF_INTERFACE_MATRICES,ERR,ERROR,*999)
        DO MID=1,INTERFACE_MATRICES%NUMBER_OF_INTERFACE_MATRICES
          CALL WRITE_STRING_VALUE(GENERAL_OUTPUT_TYPE,"Element matrix : ",MID,ERR,ERROR,*999)
          CALL WRITE_STRING_VALUE(GENERAL_OUTPUT_TYPE,"  Update matrix = ",INTERFACE_MATRICES%MATRICES(MID)%PTR% &
            & UPDATE_MATRIX,ERR,ERROR,*999)
          IF(INTERFACE_MATRICES%MATRICES(MID)%PTR%UPDATE_MATRIX) THEN
            ELEMENT_MATRIX=>INTERFACE_MATRICES%MATRICES(MID)%PTR%ELEMENT_MATRIX
            CALL WRITE_STRING_VALUE(GENERAL_OUTPUT_TYPE,"  Number of rows = ",ELEMENT_MATRIX%NUMBER_OF_ROWS,ERR,ERROR,*999)
            CALL WRITE_STRING_VALUE(GENERAL_OUTPUT_TYPE,"  Number of columns = ",ELEMENT_MATRIX%NUMBER_OF_COLUMNS, &
              & ERR,ERROR,*999)
            CALL WRITE_STRING_VALUE(GENERAL_OUTPUT_TYPE,"  Maximum number of rows = ",ELEMENT_MATRIX%MAX_NUMBER_OF_ROWS, &
              & ERR,ERROR,*999)
            CALL WRITE_STRING_VALUE(GENERAL_OUTPUT_TYPE,"  Maximum number of columns = ",ELEMENT_MATRIX% &
              & MAX_NUMBER_OF_COLUMNS,ERR,ERROR,*999)
            CALL WRITE_STRING_VECTOR(GENERAL_OUTPUT_TYPE,1,1,ELEMENT_MATRIX%NUMBER_OF_ROWS,8,8,ELEMENT_MATRIX%ROW_DOFS, &
              & '("  Row dofs     :",8(X,I13))','(16X,8(X,I13))',ERR,ERROR,*999)
            CALL WRITE_STRING_VECTOR(GENERAL_OUTPUT_TYPE,1,1,ELEMENT_MATRIX%NUMBER_OF_COLUMNS,8,8,ELEMENT_MATRIX% &
              & COLUMN_DOFS,'("  Column dofs  :",8(X,I13))','(16X,8(X,I13))',ERR,ERROR,*999)
            CALL WRITE_STRING_MATRIX(GENERAL_OUTPUT_TYPE,1,1,ELEMENT_MATRIX%NUMBER_OF_ROWS,1,1,ELEMENT_MATRIX% &
              & NUMBER_OF_COLUMNS,8,8,ELEMENT_MATRIX%MATRIX(1:ELEMENT_MATRIX%NUMBER_OF_ROWS,1:ELEMENT_MATRIX% &
              & NUMBER_OF_COLUMNS),WRITE_STRING_MATRIX_NAME_AND_INDICES,'("  Matrix','(",I2,",:)',' :",8(X,E13.6))', &
              & '(16X,8(X,E13.6))',ERR,ERROR,*999)
          ENDIF
        ENDDO !MID
      ENDIF
!    ENDIF

#ifdef TAUPROF
    CALL TAU_STATIC_PHASE_STOP("INTERFACE_CONDITION_FINITE_ELEMENT_CALCULATE()")
#endif
       
    CALL EXITS("INTERFACE_CONDITION_FINITE_ELEMENT_CALCULATE")
    RETURN
999 CALL ERRORS("INTERFACE_CONDITION_FINITE_ELEMENT_CALCULATE",ERR,ERROR)
    CALL EXITS("INTERFACE_CONDITION_FINITE_ELEMENT_CALCULATE")
    RETURN 1
    
  END SUBROUTINE INTERFACE_CONDITION_FINITE_ELEMENT_CALCULATE

  !
  !================================================================================================================================
  !

  FUNCTION INTERFACE_TRANSFORM_GPT(INTERFACE_MESH_CONNECTIVITY,ELEMENT_NUMBER,DOMAIN_NUMBER,GAUSSPT,ERR,ERROR)
  
    !Argument variables
    TYPE(INTERFACE_MESH_CONNECTIVITY_TYPE), POINTER :: INTERFACE_MESH_CONNECTIVITY !<A pointer to the interface meshes connectivity to finish creating
    INTEGER(INTG), INTENT(IN) :: ELEMENT_NUMBER !< Index to the element number
    INTEGER(INTG), INTENT(IN) :: DOMAIN_NUMBER !< Index to the domain number
    INTEGER(INTG), INTENT(IN) :: GAUSSPT !< Index to the element coupled list
    INTEGER(INTG), INTENT(OUT) :: ERR !<The error code
    TYPE(VARYING_STRING), INTENT(OUT) :: ERROR !<The error string
    !Function variable
    REAL(DP) :: INTERFACE_TRANSFORM_GPT(SIZE(INTERFACE_MESH_CONNECTIVITY%ELEMENTS_CONNECTIVITY &
      & (ELEMENT_NUMBER,DOMAIN_NUMBER)%XI,1))
    !Local Variables
    INTEGER(INTG) :: ms

    CALL ENTERS("INTERFACE_TRANSFORM_GPT",ERR,ERROR,*999)
    
    INTERFACE_TRANSFORM_GPT=0.0_DP
    IF(.NOT.ASSOCIATED(INTERFACE_MESH_CONNECTIVITY)) CALL FLAG_ERROR("Mesh Connectivity is not associated.",ERR,ERROR,*999)
    IF(.NOT.ALLOCATED(INTERFACE_MESH_CONNECTIVITY%ELEMENTS_CONNECTIVITY(ELEMENT_NUMBER,DOMAIN_NUMBER)%XI)) THEN
      CALL FLAG_ERROR("Coupled Mesh xi array not allocated.",ERR,ERROR,*999)
    END IF

    DO ms = 1,INTERFACE_MESH_CONNECTIVITY%BASIS%NUMBER_OF_ELEMENT_PARAMETERS
      INTERFACE_TRANSFORM_GPT(:)= INTERFACE_TRANSFORM_GPT(:) + INTERFACE_MESH_CONNECTIVITY%BASIS%QUADRATURE%QUADRATURE_SCHEME_MAP &
         & (BASIS_DEFAULT_QUADRATURE_SCHEME)%PTR%GAUSS_BASIS_FNS(ms,NO_PART_DERIV,GAUSSPT) * INTERFACE_MESH_CONNECTIVITY% & 
         & ELEMENTS_CONNECTIVITY(ELEMENT_NUMBER,DOMAIN_NUMBER)%XI(:,1,ms)
    END DO
     
    CALL EXITS("INTERFACE_TRANSFORM_GPT")
    RETURN
999 CALL ERRORS("INTERFACE_TRANSFORM_GPT",ERR,ERROR)
    CALL EXITS("INTERFACE_TRANSFORM_GPT")
    RETURN
    
  END FUNCTION INTERFACE_TRANSFORM_GPT

  !
  !================================================================================================================================
  !

  !>Finds and returns in INTERFACE_CONDITION a pointer to the interface condition identified by USER_NUMBER in the given INTERFACE. If no interface condition with that USER_NUMBER exists INTERFACE_CONDITION is left nullified.
  SUBROUTINE INTERFACE_CONDITION_USER_NUMBER_FIND(USER_NUMBER,INTERFACE,INTERFACE_CONDITION,ERR,ERROR,*)

    !Argument variables
    INTEGER(INTG), INTENT(IN) :: USER_NUMBER !<The user number to find.
    TYPE(INTERFACE_TYPE), POINTER :: INTERFACE !<The interface to find the interface condition in.
    TYPE(INTERFACE_CONDITION_TYPE), POINTER :: INTERFACE_CONDITION !<On return a pointer to the interface condition with the given user number. If no interface condition with that user number exists then the pointer is returned as NULL. Must not be associated on entry.
    INTEGER(INTG), INTENT(OUT) :: ERR !<The error code
    TYPE(VARYING_STRING), INTENT(OUT) :: ERROR !<The error string
    !Local Variables
    INTEGER(INTG) :: interface_condition_idx
    TYPE(VARYING_STRING) :: LOCAL_ERROR

    CALL ENTERS("INTERFACE_CONDITION_USER_NUMBER_FIND",ERR,ERROR,*999)

    IF(ASSOCIATED(INTERFACE)) THEN
      IF(ASSOCIATED(INTERFACE_CONDITION)) THEN
        CALL FLAG_ERROR("Interface condition is already associated.",ERR,ERROR,*999)
      ELSE
        NULLIFY(INTERFACE_CONDITION)
        IF(ASSOCIATED(INTERFACE%INTERFACE_CONDITIONS)) THEN
          interface_condition_idx=1
          DO WHILE(interface_condition_idx<=INTERFACE%INTERFACE_CONDITIONS%NUMBER_OF_INTERFACE_CONDITIONS.AND. &
            & .NOT.ASSOCIATED(INTERFACE_CONDITION))
            IF(INTERFACE%INTERFACE_CONDITIONS%INTERFACE_CONDITIONS(interface_condition_idx)%PTR%USER_NUMBER==USER_NUMBER) THEN
              INTERFACE_CONDITION=>INTERFACE%INTERFACE_CONDITIONS%INTERFACE_CONDITIONS(interface_condition_idx)%PTR
            ELSE
              interface_condition_idx=interface_condition_idx+1
            ENDIF
          ENDDO
        ELSE
          LOCAL_ERROR="The interface conditions on interface number "// &
            & TRIM(NUMBER_TO_VSTRING(INTERFACE%USER_NUMBER,"*",ERR,ERROR))//" are not associated."
          CALL FLAG_ERROR(LOCAL_ERROR,ERR,ERROR,*999)
        ENDIF
      ENDIF
    ELSE
      CALL FLAG_ERROR("Interface is not associated.",ERR,ERROR,*999)
    ENDIF
    
    CALL EXITS("INTERFACE_CONDITION_USER_NUMBER_FIND")
    RETURN
999 CALL ERRORS("INTERFACE_CONDITION_USER_NUMBER_FIND",ERR,ERROR)
    CALL EXITS("INTERFACE_CONDITION_USER_NUMBER_FIND")
    RETURN 1
  END SUBROUTINE INTERFACE_CONDITION_USER_NUMBER_FIND

  !
  !================================================================================================================================
  !

  !>Finalises an interface conditions and deallocates all memory.
  SUBROUTINE INTERFACE_CONDITIONS_FINALISE(INTERFACE_CONDITIONS,ERR,ERROR,*) 

    !Argument variables
    TYPE(INTERFACE_CONDITIONS_TYPE), POINTER :: INTERFACE_CONDITIONS !<A pointer to the interface conditions to finalise
    INTEGER(INTG), INTENT(OUT) :: ERR !<The error code
    TYPE(VARYING_STRING), INTENT(OUT) :: ERROR !<The error string
    !Local Variables
    TYPE(INTERFACE_CONDITION_TYPE), POINTER :: INTERFACE_CONDITION
    
    CALL ENTERS("INTERFACE_CONDITIONS_FINALISE",ERR,ERROR,*999)
    
    IF(ASSOCIATED(INTERFACE_CONDITIONS)) THEN
      DO WHILE(INTERFACE_CONDITIONS%NUMBER_OF_INTERFACE_CONDITIONS>0)
        INTERFACE_CONDITION=>INTERFACE_CONDITIONS%INTERFACE_CONDITIONS(1)%PTR
        CALL INTERFACE_CONDITION_DESTROY(INTERFACE_CONDITION,ERR,ERROR,*999)
      ENDDO
      IF(ASSOCIATED(INTERFACE_CONDITIONS%INTERFACE_CONDITIONS)) DEALLOCATE(INTERFACE_CONDITIONS%INTERFACE_CONDITIONS)
      DEALLOCATE(INTERFACE_CONDITIONS)
    ENDIF
    
    CALL EXITS("INTERFACE_CONDITIONS_FINALISE")
    RETURN
999 CALL ERRORS("INTERFACE_CONDITIONS_FINALISE",ERR,ERROR)
    CALL EXITS("INTERFACE_CONDITIONS_FINALISE")
    RETURN 1
  END SUBROUTINE INTERFACE_CONDITIONS_FINALISE

  !
  !================================================================================================================================
  !
  
  !>Initialises an interface conditions for an interface.
  SUBROUTINE INTERFACE_CONDITIONS_INITIALISE(INTERFACE,ERR,ERROR,*) 

    !Argument variables
    TYPE(INTERFACE_TYPE), POINTER :: INTERFACE !<A pointer to the interface to initialise the conditions for
    INTEGER(INTG), INTENT(OUT) :: ERR !<The error code
    TYPE(VARYING_STRING), INTENT(OUT) :: ERROR !<The error string
    !Local Variables
    INTEGER(INTG) :: DUMMY_ERR
    TYPE(VARYING_STRING) :: DUMMY_ERROR,LOCAL_ERROR
     
    CALL ENTERS("INTERFACE_CONDITIONS_INITIALISE",ERR,ERROR,*998)

    IF(ASSOCIATED(INTERFACE)) THEN
      IF(ASSOCIATED(INTERFACE%INTERFACE_CONDITIONS)) THEN
        LOCAL_ERROR="Interface conditions is already associated for interface number "// &
          & TRIM(NUMBER_TO_VSTRING(INTERFACE%USER_NUMBER,"*",ERR,ERROR))//"."
        CALL FLAG_ERROR(LOCAL_ERROR,ERR,ERROR,*999)
      ELSE
        ALLOCATE(INTERFACE%INTERFACE_CONDITIONS,STAT=ERR)
        IF(ERR/=0) CALL FLAG_ERROR("Could not allocate interface interface conditions.",ERR,ERROR,*999)
        INTERFACE%INTERFACE_CONDITIONS%INTERFACE=>INTERFACE
        INTERFACE%INTERFACE_CONDITIONS%NUMBER_OF_INTERFACE_CONDITIONS=0
        NULLIFY(INTERFACE%INTERFACE_CONDITIONS%INTERFACE_CONDITIONS)
      ENDIF
    ELSE
      CALL FLAG_ERROR("Interface is not associated.",ERR,ERROR,*998)
    ENDIF
    
    CALL EXITS("INTERFACE_CONDITIONS_INITIALISE")
    RETURN
999 CALL INTERFACE_CONDITIONS_FINALISE(INTERFACE%INTERFACE_CONDITIONS,DUMMY_ERR,DUMMY_ERROR,*998)
998 CALL ERRORS("INTERFACE_CONDITIONS_INITIALISE",ERR,ERROR)
    CALL EXITS("INTERFACE_CONDITIONS_INITIALISE")
    RETURN 1
  END SUBROUTINE INTERFACE_CONDITIONS_INITIALISE

  !
  !================================================================================================================================
  !

END MODULE INTERFACE_CONDITIONS_ROUTINES
